/**
 * directoryController.js — User Directory (customers, staff, suppliers, karigars)
 *
 * Data lives on the LGP admin cluster (a PRODUCTION database shared with the
 * legacy web admin). Safety rules for this file:
 *   - NO DELETES, anywhere. Nothing here removes a document.
 *   - Creates are inserts. Edits are UPDATES of a fixed whitelist of fields
 *     only; every edit is (a) permission-gated, (b) rejected if the record was
 *     changed by someone else since it was loaded (optimistic concurrency), and
 *     (c) written to the audit log with a field-by-field before/after.
 *   - The legacy `users` collection contains password hashes -> read via an
 *     explicit field whitelist, and NEVER editable from the app.
 *   - Legacy `customers` documents only receive fields the legacy schema
 *     already has; richer data goes to app-owned collections (app_*).
 */
'use strict';

const crypto = require('crypto');
const { getConnection } = require('../config/db');
const { hasPermission } = require('../middleware/auth');
const { MAIN_BRANCH, resolveBranch, Branch } = require('../utils/branches');
const V = require('../utils/directoryValidators');
const Lookups = require('../services/directoryLookups');
const AuditLog = require('../models/AuditLog');

const models = {
    customer: () => require('../models/directory/LgpCustomer')(getConnection()),
    staffUser: () => require('../models/directory/LgpStaffUser')(getConnection()),
    staffProfile: () => require('../models/directory/DirectoryStaffProfile')(getConnection()),
    supplier: () => require('../models/directory/DirectoryParty').supplier(getConnection()),
    karigar: () => require('../models/directory/DirectoryParty').karigar(getConnection()),
    customerProfile: () => require('../models/directory/DirectoryCustomerProfile')(getConnection()),
};
const { SAFE_FIELDS } = require('../models/directory/LgpStaffUser');

// ── helpers ──────────────────────────────────────────────────────────────────
const escapeRegex = (s) => String(s).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const { str, normalizePhone } = V;

function paging(req) {
    const page = Math.max(1, parseInt(req.query.page, 10) || 1);
    const limit = Math.min(50, Math.max(1, parseInt(req.query.limit, 10) || 25));
    return { page, limit, skip: (page - 1) * limit };
}

const fail = (res, code, message, extra = {}) =>
    res.status(code).json({ success: false, message, ...extra });

function whoAmI(req) {
    return { id: String(req.user._id), name: req.user.name || req.user.username || '' };
}

/**
 * Branch for a new record: the signed-in user's own branch, automatically.
 * Only users who can manage branches may file a record under another one.
 */
async function branchFor(req, requested) {
    const want = str(requested);
    if (want && want !== (req.user.branchId || 'main') && (await hasPermission(req.user, 'directory.manageBranches'))) {
        return resolveBranch(want);
    }
    return resolveBranch(req.user.branchId);
}

// ── audit + change detection ─────────────────────────────────────────────────
const norm = (v) => (v == null ? '' : v instanceof Date ? v.toISOString().slice(0, 10) : typeof v === 'object' ? JSON.stringify(v) : String(v));

function diff(before, after, fields) {
    const out = [];
    for (const f of fields) {
        const a = norm(before[f]);
        const b = norm(after[f]);
        if (a !== b) out.push({ field: f, from: a, to: b });
    }
    return out;
}

async function audit(req, entity, entityId, label, changes, branchId) {
    if (!changes.length) return;
    try {
        await AuditLog.create({
            entity, entityId: String(entityId), entityLabel: label, action: 'update',
            by: String(req.user._id), byName: req.user.name || '', branchId, changes,
        });
    } catch (e) {
        // The edit itself already succeeded; never fail the request over the log.
        console.error('[directory] audit log write failed:', e.message);
    }
}

// Reject an edit made on stale data (someone else saved in between).
function isStale(expected, current) {
    if (!expected || !current) return false;
    const a = new Date(expected).getTime();
    const b = new Date(current).getTime();
    return !Number.isNaN(a) && !Number.isNaN(b) && a !== b;
}
const STALE_MSG = 'This record was changed by someone else since you opened it. Close it, reopen and try again so nothing gets overwritten.';

// ── Branches ─────────────────────────────────────────────────────────────────
// GET /api/directory/branches
exports.listBranches = async (req, res, next) => {
    try {
        const rows = await Branch.find({ isActive: { $ne: false } }).sort({ name: 1 }).lean();
        res.json({ success: true, data: [MAIN_BRANCH, ...rows] });
    } catch (e) { next(e); }
};

// POST /api/directory/branches   (insert only)
exports.createBranch = async (req, res, next) => {
    try {
        const b = req.body || {};
        const name = str(b.name);
        if (!name) return fail(res, 400, 'Branch name is required');
        const dupe = await Branch.findOne({ name: new RegExp(`^${escapeRegex(name)}$`, 'i') }).lean();
        if (dupe || name.toLowerCase() === MAIN_BRANCH.name.toLowerCase()) {
            return fail(res, 409, 'A branch with this name already exists');
        }
        const gstin = str(b.gstin).toUpperCase();
        if (gstin && !/^\d{2}[A-Z0-9]{13}$/.test(gstin)) return fail(res, 400, 'GSTIN must be 15 characters, like 19ABCDE1234F1Z5');
        const me = whoAmI(req);
        const doc = await Branch.create({
            name, code: str(b.code), city: str(b.city), state: str(b.state),
            phone: str(b.phone), address: str(b.address), gstin,
            createdBy: me.id, createdByName: me.name,
        });
        res.status(201).json({ success: true, data: doc });
    } catch (e) { next(e); }
};

// ── Auto-fill helpers (Bengali, pincode, IFSC) ───────────────────────────────
// POST /api/directory/translate   { name?, nickname?, address? } -> Bengali versions
exports.translate = async (req, res, next) => {
    try {
        const b = req.body || {};
        const out = {};
        await Promise.all(['name', 'nickname', 'address'].map(async (k) => {
            if (str(b[k])) out[k] = await Lookups.toBengali(str(b[k]), k === 'address' ? 'address' : 'name');
        }));
        res.json({ success: true, data: out });
    } catch (e) { next(e); }
};

// GET /api/directory/lookup/pincode/:pin
exports.lookupPincode = async (req, res, next) => {
    try {
        const r = await Lookups.pincode(req.params.pin);
        if (!r) return fail(res, 404, 'Pincode not found');
        res.json({ success: true, data: r });
    } catch (e) { next(e); }
};

// GET /api/directory/lookup/ifsc/:code
exports.lookupIfsc = async (req, res, next) => {
    try {
        const r = await Lookups.ifsc(req.params.code);
        if (!r) return fail(res, 404, 'IFSC code not found');
        res.json({ success: true, data: r });
    } catch (e) { next(e); }
};

// GET /api/directory/history/:entity/:id  — who changed this record, and how
exports.history = async (req, res, next) => {
    try {
        const { entity, id } = req.params;
        const rows = await AuditLog.find({ entity, entityId: String(id) }).sort({ at: -1 }).limit(30).lean();
        res.json({ success: true, data: rows });
    } catch (e) { next(e); }
};

// ── GET /api/directory/summary ───────────────────────────────────────────────
exports.summary = async (req, res, next) => {
    try {
        const canStaff = await hasPermission(req.user, 'directory.viewStaff');
        const [customers, suppliers, karigars, staffUsers, staffProfiles] = await Promise.all([
            models.customer().countDocuments({ is_deleted: { $ne: true } }),
            models.supplier().countDocuments({}),
            models.karigar().countDocuments({}),
            canStaff ? models.staffUser().countDocuments({}) : 0,
            canStaff ? models.staffProfile().countDocuments({}) : 0,
        ]);
        res.json({
            success: true,
            // Karigars are part of the Staff group in the app, so they are counted there.
            data: { customers, suppliers, karigars, staff: canStaff ? staffUsers + staffProfiles + karigars : null },
        });
    } catch (e) { next(e); }
};

// ── Customers ────────────────────────────────────────────────────────────────
const CUSTOMER_LIST_FIELDS =
    'customer_name customer_name_bengali address whatsapp_no mobile_no mobile_no_3 mobile_no_4 email nickname gender notification_type created_at created_by_name sl_no';
const LEGACY_PHONE_FIELDS = ['whatsapp_no', 'mobile_no', 'mobile_no_3', 'mobile_no_4'];

// What a customer wants to hear about (the website's own four choices): everything, offers only, invitations only, nothing.
const NOTIFY_TYPES = ['all', 'offers', 'invitations', 'none'];
const notifyOf = (v) => (NOTIFY_TYPES.includes(str(v)) ? str(v) : 'all');

/**
 * The Bengali name / address, when the client sent none: made here (best effort, never holding the save up for more than ~2.5 s), so a
 * customer added from any screen has it, the way the website's form fills it in. A Bengali text the person typed is never replaced.
 */
async function bengaliFor(b) {
    const out = { name: str(b.nameBengali), address: str(b.addressBengali) };
    const want = [['name', str(b.name), 'name'], ['address', str(b.address), 'address']].filter(([k, text]) => !out[k] && text.length >= 2);
    if (!want.length) return out;
    await Promise.race([
        Promise.all(want.map(async ([k, text, kind]) => { try { out[k] = (await Lookups.toBengali(text, kind)) || ''; } catch (_) { /* stays empty */ } })),
        new Promise((r) => setTimeout(r, 2500)),
    ]);
    return out;
}

// Fields compared for the audit trail
const CUSTOMER_LEGACY_AUDIT = ['customer_name', 'customer_name_bengali', 'address', 'whatsapp_no', 'mobile_no', 'mobile_no_3', 'mobile_no_4', 'email', 'nickname', 'reference_customer_id', 'notification_type'];
const CUSTOMER_PROFILE_AUDIT = ['membershipStatus', 'customerType', 'nicknameBn', 'addressBn', 'fatherName', 'gender', 'dob', 'anniversary', 'contacts', 'city', 'state', 'country', 'pincode', 'referredBy', 'businessName', 'gstNo', 'panNo', 'aadharNo', 'taxNo', 'notes', 'opening'];

// LGPAdmin-format ID: LGP + yymmdd + 3 hex (unique among app profiles): one generator, shared with the other customer flows.
const { newCustomerCode, nextSerial } = require('../services/customerStore');

// All phone numbers a legacy customer + its profile carry.
const phonesOf = (c, profile) => {
    const set = new Set(LEGACY_PHONE_FIELDS.map((f) => normalizePhone(c[f])).filter(Boolean));
    (profile?.contacts || []).forEach((k) => k.number && set.add(normalizePhone(k.number)));
    return [...set];
};

// Profiles that match a phone-digit fragment and/or a customer code.
async function profileMatches(q, digits) {
    const or = [];
    if (digits && digits.length >= 4) or.push({ 'contacts.number': new RegExp(escapeRegex(digits)) });
    if (q) or.push({ customerCode: new RegExp('^' + escapeRegex(q), 'i') });
    if (!or.length) return [];
    return models.customerProfile().find({ $or: or }).select('customerId').lean();
}

// GET /api/directory/customers?q=&page=&limit=
exports.listCustomers = async (req, res, next) => {
    try {
        const { page, limit, skip } = paging(req);
        const filter = { is_deleted: { $ne: true } };
        const q = str(req.query.q);
        if (q) {
            const rx = new RegExp(escapeRegex(q), 'i');
            const viaProfile = await profileMatches(q, q.replace(/\D/g, ''));
            filter.$or = [
                { customer_name: rx }, { customer_name_bengali: rx }, { nickname: rx },
                { whatsapp_no: rx }, { mobile_no: rx }, { mobile_no_3: rx }, { mobile_no_4: rx }, { address: rx },
                ...(viaProfile.length ? [{ _id: { $in: viaProfile.map((p) => p.customerId) } }] : []),
            ];
        }
        const Customer = models.customer();
        const [rows, total] = await Promise.all([
            Customer.find(filter).select(CUSTOMER_LIST_FIELDS).sort({ sl_no: -1, _id: -1 }).skip(skip).limit(limit).lean(),
            Customer.countDocuments(filter),
        ]);
        res.json({ success: true, data: rows, pagination: { page, limit, total, hasMore: skip + rows.length < total } });
    } catch (e) { next(e); }
};

/**
 * GET /api/directory/customers/lookup?q=...&exclude=<id>
 * Type-ahead used by the Add/Edit Customer form for (a) live duplicate
 * detection while a phone number is typed and (b) picking the "referred by"
 * customer.
 *   - digits (>=4)  -> phone search across every number a customer has
 *   - LGP... code   -> customer code
 *   - text (>=2)    -> name / nickname
 * `exact` is true when a full 10-digit number equals one of the customer's.
 * `exclude` hides one customer (the one being edited).
 */
exports.lookupCustomers = async (req, res, next) => {
    try {
        const q = str(req.query.q);
        const digits = normalizePhone(q);
        const isPhoneQuery = /^[\d\s+\-()]+$/.test(q) && digits.length >= 4;
        if (!isPhoneQuery && q.length < 2) return res.json({ success: true, data: [] });

        const Customer = models.customer();
        const filter = { is_deleted: { $ne: true } };
        if (/^[a-f0-9]{24}$/i.test(str(req.query.exclude))) filter._id = { $ne: str(req.query.exclude) };
        const or = [];
        if (isPhoneQuery) {
            const rx = new RegExp(escapeRegex(digits));
            const viaProfile = await profileMatches('', digits);
            or.push(...LEGACY_PHONE_FIELDS.map((f) => ({ [f]: rx })),
                ...(viaProfile.length ? [{ _id: { $in: viaProfile.map((p) => p.customerId) } }] : []));
        } else {
            const rx = new RegExp(escapeRegex(q), 'i');
            const viaCode = await profileMatches(q, '');
            or.push({ customer_name: rx }, { customer_name_bengali: rx }, { nickname: rx },
                ...(viaCode.length ? [{ _id: { $in: viaCode.map((p) => p.customerId) } }] : []));
        }
        filter.$and = [{ $or: or }];
        const rows = await Customer.find(filter).select(CUSTOMER_LIST_FIELDS).sort({ sl_no: -1 }).limit(8).lean();
        const profiles = await models.customerProfile()
            .find({ customerId: { $in: rows.map((r) => r._id) } }).select('customerId customerCode contacts branchName').lean();
        const byId = new Map(profiles.map((p) => [String(p.customerId), p]));

        const data = rows.map((c) => {
            const p = byId.get(String(c._id));
            const phones = phonesOf(c, p);
            return {
                id: String(c._id),
                name: c.customer_name || c.customer_name_bengali || '(No name)',
                nameBn: c.customer_name_bengali || '',
                code: p?.customerCode || null,
                serialNo: c.sl_no || null,
                phones,
                matchedNumber: isPhoneQuery ? phones.find((n) => n.includes(digits)) || null : null,
                exact: isPhoneQuery && digits.length === 10 && phones.includes(digits),
                branch: p?.branchName || null,
                address: c.address || '',
            };
        });
        res.json({ success: true, data });
    } catch (e) { next(e); }
};

const CUSTOMER_DETAIL_FIELDS = CUSTOMER_LIST_FIELDS + ' address_bengali reference_customer_id anniversaries updated_at updated_by_name';

async function customerWithProfile(id) {
    const doc = await models.customer().findOne({ _id: id, is_deleted: { $ne: true } }).select(CUSTOMER_DETAIL_FIELDS).lean();
    if (!doc) return null;
    const profile = await models.customerProfile().findOne({ customerId: doc._id }).lean();
    return { ...doc, profile: profile || null };
}

// GET /api/directory/customers/:id
exports.getCustomer = async (req, res, next) => {
    try {
        const data = await customerWithProfile(req.params.id);
        if (!data) return fail(res, 404, 'Customer not found');
        res.json({ success: true, data });
    } catch (e) {
        if (e.name === 'CastError') return fail(res, 400, 'Invalid customer id');
        next(e);
    }
};

const MOBILE_LABELS = ['whatsapp', 'mobile'];

// Accepts the new `contacts: [{number,label}]`, or the older whatsappNo/mobileNo pair.
function parseContacts(b) {
    let list = Array.isArray(b.contacts) ? b.contacts : null;
    if (!list) {
        list = [];
        if (str(b.whatsappNo)) list.push({ number: b.whatsappNo, label: 'whatsapp' });
        if (str(b.mobileNo)) list.push({ number: b.mobileNo, label: 'mobile' });
    }
    return list
        .map((c) => ({
            number: normalizePhone(c && c.number),
            label: ['whatsapp', 'mobile', 'home', 'work', 'other'].includes(c && c.label) ? c.label : 'mobile',
        }))
        .filter((c) => c.number);
}

// "Important dates" (the website's `anniversaries`): any number of { occasion, date } - birthday, marriage anniversary,
// engagement, work anniversary, or anything else. undefined = the client did not send the list (what is saved stays);
// [] = clear it.
const MAX_DATES = 12;
function importantDatesOf(b) {
    if (!Array.isArray(b.importantDates)) return { list: undefined };
    const list = [];
    for (const row of b.importantDates) {
        const occasion = str(row && row.occasion);
        const raw = str(row && row.date).slice(0, 10);
        if (!occasion && !raw) continue;                         // an empty row is just dropped
        if (!occasion || !raw) return { error: 'Each important date needs both an occasion and a date' };
        const d = new Date(raw + 'T00:00:00.000Z');
        if (!/^\d{4}-\d{2}-\d{2}$/.test(raw) || Number.isNaN(d.getTime()) || d.getUTCFullYear() < 1900 || d.getUTCFullYear() > 2100) return { error: `"${raw}" is not a valid date` };
        if (occasion.length > 40) return { error: 'The occasion is too long (40 letters at most)' };
        if (!list.some((x) => x.occasion.toLowerCase() === occasion.toLowerCase() && x.date.getTime() === d.getTime())) list.push({ occasion, date: d });
    }
    if (list.length > MAX_DATES) return { error: `At most ${MAX_DATES} important dates` };
    return { list };
}
const isBirthday = (o) => /birth/i.test(o);
const isMarriage = (o) => /marriage|wedding|anniversary/i.test(o) && !/work|job|business/i.test(o);

/** The list to store: the one sent, else (older clients) what the single birth date / anniversary fields say. */
function datesForSave(p, b) {
    if (p.importantDates !== undefined) return p.importantDates;
    const out = [];
    if (b.dob) out.push({ occasion: 'Birthday', date: new Date(b.dob) });
    if (p.anniversary) out.push({ occasion: 'Marriage Anniversary', date: p.anniversary });
    return out.length ? out : undefined;
}

// The stored list for a partial edit; the profile's single birth date / anniversary (older app versions) join it when the list lacks them.
function datesBase(cur, pr, day) {
    const list = (cur.anniversaries || []).map((a) => ({ occasion: a.occasion, date: day(a.date) }));
    if (pr.dob && !list.some((x) => isBirthday(x.occasion))) list.push({ occasion: 'Birthday', date: day(pr.dob) });
    if (pr.anniversary && !list.some((x) => isMarriage(x.occasion))) list.push({ occasion: 'Marriage Anniversary', date: day(pr.anniversary) });
    return list;
}

// Validate + normalise a customer payload (shared by create and update).
function parseCustomer(b) {
    const name = str(b.name);
    if (name.length < 2) return { error: 'Customer name is required' };

    const contacts = parseContacts(b);
    if (!contacts.length) return { error: 'Enter at least one phone number' };
    if (contacts.length > 6) return { error: 'A customer can have at most 6 phone numbers' };
    contacts[0].label = contacts[0].label === 'mobile' ? 'mobile' : 'whatsapp';
    for (const c of contacts) {
        const ok = MOBILE_LABELS.includes(c.label) ? V.isMobile10(c.number) : V.isPhone10(c.number);
        if (!ok) return { error: `"${c.number}" is not a valid 10-digit ${MOBILE_LABELS.includes(c.label) ? 'mobile ' : ''}number` };
    }
    const seen = new Set();
    for (const c of contacts) {
        if (seen.has(c.number)) return { error: `The number ${c.number} is entered more than once` };
        seen.add(c.number);
    }
    const bad = V.validateCommon(b);
    if (bad) return { error: bad };
    const dates = importantDatesOf(b);
    if (dates.error) return { error: dates.error };

    return {
        data: {
            name, contacts, importantDates: dates.list,
            gender: ['Male', 'Female', 'Other'].includes(b.gender) ? b.gender : '',
            membershipStatus: b.membershipStatus === 'VIP' ? 'VIP' : 'Regular',
            anniversary: b.anniversary ? new Date(b.anniversary) : null,
        },
    };
}

// A different (non-deleted) customer already using any of these numbers?
async function findCustomerDuplicate(contacts, excludeId) {
    const nums = contacts.map((c) => c.number);
    const viaProfile = await models.customerProfile().find({ 'contacts.number': { $in: nums } }).select('customerId').lean();
    const filter = {
        is_deleted: { $ne: true },
        $or: [
            ...LEGACY_PHONE_FIELDS.map((f) => ({ [f]: { $in: nums } })),
            ...(viaProfile.length ? [{ _id: { $in: viaProfile.map((p) => p.customerId) } }] : []),
        ],
    };
    if (excludeId) filter._id = { ...(filter._id || {}), $ne: excludeId };
    return models.customer().findOne(filter).select('customer_name whatsapp_no mobile_no').lean();
}

// "Referred by": must point at a real customer (never the customer itself).
async function resolveReferral(b, selfId) {
    if (str(b.referredById)) {
        if (selfId && String(b.referredById) === String(selfId)) return { error: 'A customer cannot be referred by themselves' };
        let ref;
        try { ref = await models.customer().findOne({ _id: b.referredById, is_deleted: { $ne: true } }).select(CUSTOMER_LIST_FIELDS).lean(); }
        catch (_) { ref = null; }
        if (!ref) return { error: 'The customer selected in "Referred by" was not found' };
        const p = await models.customerProfile().findOne({ customerId: ref._id }).select('customerCode').lean();
        return {
            referenceId: String(ref._id),
            referredBy: { customerId: ref._id, code: p?.customerCode, name: ref.customer_name, mobile: ref.whatsapp_no || ref.mobile_no },
        };
    }
    if (str(b.referredByText)) return { referenceId: '', referredBy: { text: str(b.referredByText) } };
    return { referenceId: '', referredBy: undefined };
}

const bal = (o) => ({ amount: Number(o?.amount) || 0, type: o?.type === 'debit' ? 'debit' : 'credit' });
const wt = (o) => ({ weight: Number(o?.weight) || 0, unit: o?.unit === 'kg' ? 'kg' : 'gram', type: o?.type === 'debit' ? 'debit' : 'credit' });
const openingOf = (b) => {
    const op = (b && b.opening) || {};
    return { date: op.date ? new Date(op.date) : undefined, cash: bal(op.cash), gold: wt(op.gold), silver: wt(op.silver) };
};

// Profile fields (identical for create and update)
function customerProfileFields(b, parsed, referral) {
    return {
        membershipStatus: parsed.membershipStatus, customerType: str(b.customerType),
        nicknameBn: str(b.nicknameBengali), addressBn: str(b.addressBengali),
        fatherName: str(b.fatherName), gender: parsed.gender,
        // the single birth date / anniversary follow the list of important dates when the client sends it
        dob: parsed.importantDates ? ((parsed.importantDates.find((x) => isBirthday(x.occasion)) || {}).date || null) : (b.dob ? new Date(b.dob) : undefined),
        anniversary: parsed.importantDates ? ((parsed.importantDates.find((x) => isMarriage(x.occasion)) || {}).date || null) : (parsed.anniversary || undefined),
        contacts: parsed.contacts,
        city: str(b.city), state: str(b.state),
        country: str(b.country) || 'India', pincode: str(b.pincode),
        referredBy: referral.referredBy,
        businessName: str(b.businessName),
        gstNo: str(b.gstNo), panNo: str(b.panNo), aadharNo: str(b.aadharNo).replace(/\s/g, ''), taxNo: str(b.taxNo),
        notes: str(b.notes),
        opening: openingOf(b),
    };
}

// POST /api/directory/customers   (insert only)
exports.createCustomer = async (req, res, next) => {
    try {
        const b = req.body || {};
        const parsed = parseCustomer(b);
        if (parsed.error) return fail(res, 400, parsed.error);
        const { data: p } = parsed;
        const Customer = models.customer();

        if (b.force !== true) {
            const dupe = await findCustomerDuplicate(p.contacts);
            if (dupe) {
                return fail(res, 409, `A customer with one of these numbers already exists: ${dupe.customer_name || 'unnamed'}`, {
                    duplicate: { id: dupe._id, name: dupe.customer_name },
                });
            }
        }

        const referral = await resolveReferral(b);
        if (referral.error) return fail(res, 400, referral.error);
        const bn = await bengaliFor(b);

        const now = new Date();
        const me = whoAmI(req);
        const branch = await branchFor(req, b.branchId);

        const doc = await Customer.create({
            customer_name: p.name,
            customer_name_bengali: bn.name,
            address: str(b.address),
            address_bengali: bn.address,
            whatsapp_no: p.contacts[0].number,
            mobile_no: p.contacts[1] ? p.contacts[1].number : '',
            mobile_no_3: p.contacts[2] ? p.contacts[2].number : undefined,
            mobile_no_4: p.contacts[3] ? p.contacts[3].number : undefined,
            email: str(b.email) || undefined,
            nickname: str(b.nickname) || undefined,
            reference_customer_id: referral.referenceId || undefined,
            anniversaries: datesForSave(p, b),
            notification_type: notifyOf(b.notificationType),
            created_by: me.id,
            created_by_name: me.name,
            created_at: now,
            updated_at: now,
            sl_no: await nextSerial(),   // the website's rule: highest among customers that are not deleted, plus one
        });

        const profile = await models.customerProfile().create({
            customerId: doc._id,
            customerCode: await newCustomerCode(),
            ...branch,
            ...customerProfileFields({ ...b, addressBengali: bn.address }, p, referral),
            source: str(req.headers['x-client']).toLowerCase() === 'portal' ? 'portal' : 'app',
            createdBy: me.id, createdByName: me.name,
        });
        res.status(201).json({ success: true, data: { ...doc.toObject(), profile: profile.toObject() } });
    } catch (e) { next(e); }
};

/**
 * PUT /api/directory/customers/:id   (guarded update)
 * Body: the same fields as create, plus `expectedUpdatedAt` (the `updated_at`
 * the client loaded). Nothing is ever deleted; the customer's legacy document
 * gets only its known fields, and richer data goes to the app profile (which
 * is created on first edit for older customers, giving them a customer code).
 */
exports.updateCustomer = async (req, res, next) => {
    try {
        const b = req.body || {};
        const Customer = models.customer();
        const before = await Customer.findOne({ _id: req.params.id, is_deleted: { $ne: true } }).lean();
        if (!before) return fail(res, 404, 'Customer not found');
        if (isStale(b.expectedUpdatedAt, before.updated_at)) return fail(res, 409, STALE_MSG, { conflict: true });

        const parsed = parseCustomer(b);
        if (parsed.error) return fail(res, 400, parsed.error);
        const { data: p } = parsed;

        // only a number this customer did not already have can clash (an existing duplicate must not block editing something else)
        const hadProfile = await models.customerProfile().findOne({ customerId: before._id }).select('contacts').lean();
        const had = new Set([...LEGACY_PHONE_FIELDS.map((f) => before[f]), ...((hadProfile && hadProfile.contacts) || []).map((c) => c.number)].filter(Boolean));
        const added = p.contacts.filter((c) => !had.has(c.number));
        if (b.force !== true && added.length) {
            const dupe = await findCustomerDuplicate(added, before._id);
            if (dupe) {
                return fail(res, 409, `Another customer already uses one of these numbers: ${dupe.customer_name || 'unnamed'}`, {
                    duplicate: { id: dupe._id, name: dupe.customer_name },
                });
            }
        }
        const referral = await resolveReferral(b, before._id);
        if (referral.error) return fail(res, 400, referral.error);

        const me = whoAmI(req);
        const now = new Date();
        const $set = {
            customer_name: p.name,
            customer_name_bengali: str(b.nameBengali),
            address: str(b.address),
            address_bengali: str(b.addressBengali),
            whatsapp_no: p.contacts[0].number,
            mobile_no: p.contacts[1] ? p.contacts[1].number : '',
            notification_type: notifyOf(b.notificationType),
            updated_at: now, updated_by: me.id, updated_by_name: me.name,
        };
        const $unset = {};
        // Optional legacy fields: set when present, remove when cleared.
        const optional = {
            mobile_no_3: p.contacts[2] && p.contacts[2].number,
            mobile_no_4: p.contacts[3] && p.contacts[3].number,
            email: str(b.email),
            nickname: str(b.nickname),
            reference_customer_id: referral.referenceId,
        };
        for (const [k, v] of Object.entries(optional)) { if (v) $set[k] = v; else $unset[k] = ''; }
        // The list the client sent replaces the saved one (an empty list clears it). From a client that sends only the single
        // anniversary field, an existing list is never overwritten.
        if (p.importantDates !== undefined) {
            $set.anniversaries = p.importantDates;
        } else if (!(before.anniversaries && before.anniversaries.length) && p.anniversary) {
            $set.anniversaries = [{ occasion: 'Marriage Anniversary', date: p.anniversary }];
        }
        await Customer.updateOne({ _id: before._id }, { $set, ...(Object.keys($unset).length ? { $unset } : {}) });

        // App profile: update, or create on first edit (backfills a customer code).
        const Profile = models.customerProfile();
        const profBefore = await Profile.findOne({ customerId: before._id }).lean();
        const fields = customerProfileFields(b, p, referral);
        const branchSet = {};
        if (str(b.branchId) && (await hasPermission(req.user, 'directory.manageBranches'))) Object.assign(branchSet, await resolveBranch(b.branchId));
        if (profBefore) {
            await Profile.updateOne({ customerId: before._id }, { $set: { ...fields, ...branchSet } });
        } else {
            await Profile.create({
                customerId: before._id, customerCode: await newCustomerCode(),
                ...(await resolveBranch('main')), ...fields, ...branchSet,
                source: 'shopmanage', sourceId: String(before._id), createdBy: me.id, createdByName: me.name,
            });
        }

        const afterLegacy = { ...before, ...$set };
        Object.keys($unset).forEach((k) => delete afterLegacy[k]);
        const profAfter = await Profile.findOne({ customerId: before._id }).lean();
        await audit(req, 'customer', before._id, p.name, [
            ...diff(before, afterLegacy, CUSTOMER_LEGACY_AUDIT),
            ...diff(profBefore || {}, profAfter || {}, CUSTOMER_PROFILE_AUDIT),
        ], profAfter && profAfter.branchId);

        res.json({ success: true, data: await customerWithProfile(before._id) });
    } catch (e) { next(e); }
};

/**
 * PUT /api/directory/customers/:id/partial  (for clients that only edit a few fields, e.g. the website)
 * Takes the same body as the full update but only the fields that should change: everything else is filled in from what is
 * stored, so a partial edit can never clear phone numbers, opening balance, referral or the other details.
 */
exports.patchCustomer = async (req, res, next) => {
    try {
        const cur = await customerWithProfile(req.params.id);
        if (!cur) return fail(res, 404, 'Customer not found');
        const pr = cur.profile || {};
        const legacy = [[cur.whatsapp_no, 'whatsapp'], [cur.mobile_no, 'mobile'], [cur.mobile_no_3, 'mobile'], [cur.mobile_no_4, 'mobile']].filter((x) => x[0]).map((x) => ({ number: x[0], label: x[1] }));
        const day = (d) => (d ? new Date(d).toISOString().slice(0, 10) : undefined);
        const base = {
            name: cur.customer_name, nameBengali: cur.customer_name_bengali, address: cur.address, email: cur.email, nickname: cur.nickname,
            notificationType: cur.notification_type,
            contacts: (pr.contacts && pr.contacts.length ? pr.contacts : legacy).map((c) => ({ number: c.number, label: c.label })),
            gender: pr.gender, membershipStatus: pr.membershipStatus, customerType: pr.customerType, nicknameBengali: pr.nicknameBn, addressBengali: pr.addressBn || cur.address_bengali,
            importantDates: datesBase(cur, pr, day),
            fatherName: pr.fatherName, dob: day(pr.dob), anniversary: day(pr.anniversary), city: pr.city, state: pr.state, country: pr.country, pincode: pr.pincode,
            businessName: pr.businessName, gstNo: pr.gstNo, panNo: pr.panNo, aadharNo: pr.aadharNo, taxNo: pr.taxNo, notes: pr.notes, opening: pr.opening,
            referredById: pr.referredBy && pr.referredBy.customerId ? String(pr.referredBy.customerId) : undefined,
            referredByText: pr.referredBy && !pr.referredBy.customerId ? pr.referredBy.text : undefined,
            expectedUpdatedAt: cur.updated_at,
        };
        req.body = { ...base, ...(req.body || {}) };
        return exports.updateCustomer(req, res, next);
    } catch (e) { next(e); }
};

// ── Staff (legacy login users, read-only + new HR profiles) ──────────────────
// GET /api/directory/staff?q=   (login users + HR profiles + karigars)
exports.listStaff = async (req, res, next) => {
    try {
        const q = str(req.query.q);
        const rx = q ? new RegExp(escapeRegex(q), 'i') : null;

        const userFilter = rx ? { $or: [{ full_name: rx }, { username: rx }, { contact: rx }, { email: rx }] } : {};
        const profileFilter = rx ? { $or: [{ firstName: rx }, { lastName: rx }, { mobile: rx }, { email: rx }] } : {};
        const karigarFilter = rx
            ? { $or: [{ firstName: rx }, { lastName: rx }, { firmName: rx }, { mobile: rx }, { city: rx }] }
            : {};

        // Both sets are tiny (a dozen or so), so merge in memory.
        const [users, profiles, karigars] = await Promise.all([
            models.staffUser().find(userFilter).select(SAFE_FIELDS).sort({ full_name: 1 }).lean(),
            models.staffProfile().find(profileFilter).sort({ firstName: 1 }).lean(),
            models.karigar().find(karigarFilter).sort({ firstName: 1 }).lean(),
        ]);

        const rows = [
            ...users.map((u) => ({
                id: String(u._id), source: 'login',
                name: u.full_name || u.username, role: u.role, mobile: u.contact, email: u.email,
                address: u.address, active: u.is_active !== false && u.status === 'active', lastLogin: u.last_login,
            })),
            ...profiles.map((p) => ({
                id: String(p._id), source: 'profile',
                name: [p.firstName, p.lastName].filter(Boolean).join(' '),
                role: p.employment?.designation || p.employment?.department || 'Staff',
                mobile: p.mobile, email: p.email, address: p.address, active: true,
            })),
            ...karigars.map((k) => ({
                id: String(k._id), source: 'karigar',
                name: [k.firstName, k.lastName].filter(Boolean).join(' '),
                role: 'Karigar', mobile: k.mobile, email: k.email,
                address: [k.firmName, k.city].filter(Boolean).join(', '), active: true,
            })),
        ];
        res.json({ success: true, data: rows, pagination: { page: 1, limit: rows.length, total: rows.length, hasMore: false } });
    } catch (e) { next(e); }
};

// GET /api/directory/staff/:source/:id
exports.getStaff = async (req, res, next) => {
    try {
        const { source, id } = req.params;
        let doc;
        if (source === 'login') doc = await models.staffUser().findById(id).select(SAFE_FIELDS).lean();
        else if (source === 'profile') doc = await models.staffProfile().findById(id).lean();
        else if (source === 'karigar') doc = await models.karigar().findById(id).lean();
        else return fail(res, 400, 'Unknown staff source');
        if (!doc) return fail(res, 404, 'Staff member not found');
        res.json({ success: true, data: { source, ...doc } });
    } catch (e) {
        if (e.name === 'CastError') return fail(res, 400, 'Invalid staff id');
        next(e);
    }
};

// Validate + normalise a staff payload
function parseStaff(b) {
    const mobile = normalizePhone(b.mobile);
    if (!str(b.firstName)) return { error: 'First name is required' };
    if (!V.isMobile10(mobile)) return { error: 'Mobile number must be a valid 10-digit number' };
    if (str(b.emergencyContactPhone) && !V.isPhone10(normalizePhone(b.emergencyContactPhone))) {
        return { error: 'Emergency phone must be 10 digits' };
    }
    const bad = V.validateCommon({ ...b, bank: (b.employment || {}).bank });
    if (bad) return { error: bad };
    return { mobile };
}

function staffFields(b, mobile) {
    const e = b.employment || {};
    return {
        firstName: str(b.firstName), lastName: str(b.lastName),
        dob: b.dob ? new Date(b.dob) : undefined,
        gender: b.gender === 'F' ? 'F' : 'M',
        mobile, phone: str(b.phone), email: str(b.email),
        maritalStatus: str(b.maritalStatus),
        emergencyContactName: str(b.emergencyContactName),
        emergencyContactPhone: normalizePhone(b.emergencyContactPhone),
        address: str(b.address), city: str(b.city), state: str(b.state),
        country: str(b.country) || 'India', pincode: str(b.pincode),
        panNo: str(b.panNo), aadharNo: str(b.aadharNo).replace(/\s/g, ''),
        education: {
            degree: str(b.education?.degree), institution: str(b.education?.institution),
            passingYear: str(b.education?.passingYear), certifications: str(b.education?.certifications),
        },
        employment: {
            department: str(e.department), designation: str(e.designation),
            salary: Number(e.salary) || 0,
            startDate: e.startDate ? new Date(e.startDate) : undefined,
            bank: { name: str(e.bank?.name), accountName: str(e.bank?.accountName), accountNo: str(e.bank?.accountNo), ifsc: str(e.bank?.ifsc) },
            previousCompany: str(e.previousCompany), previousDesignation: str(e.previousDesignation),
        },
    };
}
const STAFF_AUDIT = ['firstName', 'lastName', 'dob', 'gender', 'mobile', 'phone', 'email', 'maritalStatus', 'emergencyContactName', 'emergencyContactPhone', 'address', 'city', 'state', 'country', 'pincode', 'panNo', 'aadharNo', 'education', 'employment'];

// POST /api/directory/staff  (creates an HR profile; never touches legacy `users`)
exports.createStaff = async (req, res, next) => {
    try {
        const b = req.body || {};
        const parsed = parseStaff(b);
        if (parsed.error) return fail(res, 400, parsed.error);
        if (b.force !== true) {
            const dupe = await models.staffProfile().findOne({ mobile: parsed.mobile }).select('firstName lastName').lean();
            if (dupe) {
                return fail(res, 409, `This mobile number is already saved for ${[dupe.firstName, dupe.lastName].filter(Boolean).join(' ')}`, {
                    duplicate: { id: dupe._id },
                });
            }
        }
        const me = whoAmI(req);
        const branch = await branchFor(req, b.branchId);
        const doc = await models.staffProfile().create({
            ...branch, ...staffFields(b, parsed.mobile), createdBy: me.id, createdByName: me.name,
        });
        res.status(201).json({ success: true, data: doc });
    } catch (e) { next(e); }
};

// PUT /api/directory/staff/profile/:id   (HR profiles only — never login accounts)
exports.updateStaff = async (req, res, next) => {
    try {
        const b = req.body || {};
        const Model = models.staffProfile();
        const before = await Model.findById(req.params.id).lean();
        if (!before) return fail(res, 404, 'Staff member not found');
        if (isStale(b.expectedUpdatedAt, before.updatedAt)) return fail(res, 409, STALE_MSG, { conflict: true });
        const parsed = parseStaff(b);
        if (parsed.error) return fail(res, 400, parsed.error);
        if (b.force !== true) {
            const dupe = await Model.findOne({ mobile: parsed.mobile, _id: { $ne: before._id } }).select('firstName lastName').lean();
            if (dupe) return fail(res, 409, `This mobile number belongs to ${[dupe.firstName, dupe.lastName].filter(Boolean).join(' ')}`, { duplicate: { id: dupe._id } });
        }
        const me = whoAmI(req);
        const $set = { ...staffFields(b, parsed.mobile), updatedBy: me.id, updatedByName: me.name };
        if (str(b.branchId) && (await hasPermission(req.user, 'directory.manageBranches'))) Object.assign($set, await resolveBranch(b.branchId));
        await Model.updateOne({ _id: before._id }, { $set });
        const after = await Model.findById(before._id).lean();
        await audit(req, 'staff', before._id, [before.firstName, before.lastName].filter(Boolean).join(' '), diff(before, after, STAFF_AUDIT), after.branchId);
        res.json({ success: true, data: after });
    } catch (e) { next(e); }
};

// ── Suppliers & Karigars (shared handlers) ───────────────────────────────────
const PARTY_AUDIT = ['partyType', 'firmName', 'firstName', 'lastName', 'fatherName', 'gender', 'mobile', 'phone', 'email', 'reference', 'address', 'city', 'state', 'country', 'pincode', 'businessName', 'gstNo', 'panNo', 'aadharNo', 'taxNo', 'bank', 'nominee', 'opening'];

function parseParty(b) {
    const mobile = normalizePhone(b.mobile);
    if (!str(b.firstName)) return { error: 'Name is required' };
    if (!V.isMobile10(mobile)) return { error: 'Mobile number must be a valid 10-digit number' };
    const bad = V.validateCommon(b);
    if (bad) return { error: bad };
    return { mobile };
}

function partyFields(b, mobile) {
    return {
        partyType: str(b.partyType), firmName: str(b.firmName),
        firstName: str(b.firstName), lastName: str(b.lastName), fatherName: str(b.fatherName),
        gender: b.gender === 'F' ? 'F' : 'M',
        mobile, phone: str(b.phone), email: str(b.email), reference: str(b.reference),
        address: str(b.address), city: str(b.city), state: str(b.state),
        country: str(b.country) || 'India', pincode: str(b.pincode),
        businessName: str(b.businessName), gstNo: str(b.gstNo), panNo: str(b.panNo),
        aadharNo: str(b.aadharNo).replace(/\s/g, ''), taxNo: str(b.taxNo),
        bank: { name: str(b.bank?.name), accountName: str(b.bank?.accountName), accountNo: str(b.bank?.accountNo), ifsc: str(b.bank?.ifsc) },
        nominee: { name: str(b.nominee?.name), relation: str(b.nominee?.relation) },
        opening: openingOf(b),
    };
}

const partyList = (key) => async (req, res, next) => {
    try {
        const { page, limit, skip } = paging(req);
        const q = str(req.query.q);
        const filter = {};
        if (q) {
            const rx = new RegExp(escapeRegex(q), 'i');
            filter.$or = [{ firstName: rx }, { lastName: rx }, { firmName: rx }, { businessName: rx }, { mobile: rx }, { city: rx }];
        }
        const Model = models[key]();
        const [rows, total] = await Promise.all([
            Model.find(filter).sort({ createdAt: -1 }).skip(skip).limit(limit).lean(),
            Model.countDocuments(filter),
        ]);
        res.json({ success: true, data: rows, pagination: { page, limit, total, hasMore: skip + rows.length < total } });
    } catch (e) { next(e); }
};

const partyGet = (key) => async (req, res, next) => {
    try {
        const doc = await models[key]().findById(req.params.id).lean();
        if (!doc) return fail(res, 404, 'Record not found');
        res.json({ success: true, data: doc });
    } catch (e) {
        if (e.name === 'CastError') return fail(res, 400, 'Invalid id');
        next(e);
    }
};

const partyCreate = (key) => async (req, res, next) => {
    try {
        const b = req.body || {};
        const parsed = parseParty(b);
        if (parsed.error) return fail(res, 400, parsed.error);

        const Model = models[key]();
        if (b.force !== true) {
            const dupe = await Model.findOne({ mobile: parsed.mobile }).select('firstName lastName').lean();
            if (dupe) {
                return fail(res, 409, `This mobile number is already saved for ${[dupe.firstName, dupe.lastName].filter(Boolean).join(' ')}`, {
                    duplicate: { id: dupe._id },
                });
            }
        }
        const me = whoAmI(req);
        const branch = await branchFor(req, b.branchId);
        const doc = await Model.create({ ...branch, ...partyFields(b, parsed.mobile), createdBy: me.id, createdByName: me.name });
        res.status(201).json({ success: true, data: doc });
    } catch (e) { next(e); }
};

const partyUpdate = (key, entity) => async (req, res, next) => {
    try {
        const b = req.body || {};
        const Model = models[key]();
        const before = await Model.findById(req.params.id).lean();
        if (!before) return fail(res, 404, 'Record not found');
        if (isStale(b.expectedUpdatedAt, before.updatedAt)) return fail(res, 409, STALE_MSG, { conflict: true });
        const parsed = parseParty(b);
        if (parsed.error) return fail(res, 400, parsed.error);
        if (b.force !== true) {
            const dupe = await Model.findOne({ mobile: parsed.mobile, _id: { $ne: before._id } }).select('firstName lastName').lean();
            if (dupe) return fail(res, 409, `This mobile number belongs to ${[dupe.firstName, dupe.lastName].filter(Boolean).join(' ')}`, { duplicate: { id: dupe._id } });
        }
        const me = whoAmI(req);
        const $set = { ...partyFields(b, parsed.mobile), updatedBy: me.id, updatedByName: me.name };
        if (str(b.branchId) && (await hasPermission(req.user, 'directory.manageBranches'))) Object.assign($set, await resolveBranch(b.branchId));
        await Model.updateOne({ _id: before._id }, { $set });
        const after = await Model.findById(before._id).lean();
        await audit(req, entity, before._id, [before.firstName, before.lastName].filter(Boolean).join(' '), diff(before, after, PARTY_AUDIT), after.branchId);
        res.json({ success: true, data: after });
    } catch (e) { next(e); }
};

exports.listSuppliers = partyList('supplier');
exports.getSupplier = partyGet('supplier');
exports.createSupplier = partyCreate('supplier');
exports.updateSupplier = partyUpdate('supplier', 'supplier');
exports.listKarigars = partyList('karigar');
exports.getKarigar = partyGet('karigar');
exports.createKarigar = partyCreate('karigar');
exports.updateKarigar = partyUpdate('karigar', 'karigar');

/**
 * Make sure a customer has an app profile (and therefore an LGP customer code).
 * Used by billing: an invoice references the customer by that code. Creates
 * only an app-owned profile row; the legacy customer document is untouched.
 */
exports.ensureCustomerProfile = async (customerId, me) => {
    const Profile = models.customerProfile();
    const existing = await Profile.findOne({ customerId }).lean();
    if (existing) return existing;
    const created = await Profile.create({
        customerId, customerCode: await newCustomerCode(),
        ...(await resolveBranch('main')),
        source: 'shopmanage', sourceId: String(customerId),
        createdBy: me && me.id, createdByName: me && me.name,
    });
    return created.toObject();
};
