/**
 * customerStore.js - the ONE way the app finds and makes customers.
 *
 * The website's `customers` collection (in use for 1.5 years) is the master: the app works with its records and its
 * rules, it does not keep a customer list of its own.
 *   - a customer can have up to four numbers (whatsapp_no, mobile_no, mobile_no_3, mobile_no_4): a person is found by ANY of them;
 *   - a new customer is written exactly as the website's "add customer" page writes one (same fields, a serial number
 *     `sl_no` = the highest among customers that are not deleted + 1, is_deleted:false);
 *   - what the website knows about a customer is never overwritten from here (names and addresses are edited through the
 *     directory, which checks the record has not changed meanwhile and writes an audit line);
 *   - what only the app knows (customer code, wishlist, bookings ...) lives next to it in `app_customer_profiles`.
 */
'use strict';
const crypto = require('crypto');
const { getConnection } = require('../config/db');
const V = require('../utils/directoryValidators');

const PHONE_FIELDS = ['whatsapp_no', 'mobile_no', 'mobile_no_3', 'mobile_no_4'];
const Customer = () => require('../models/directory/LgpCustomer')(getConnection());
const Profile = () => require('../models/directory/DirectoryCustomerProfile')(getConnection());
const notDeleted = { is_deleted: { $ne: true } };

/** The 10 digits of a phone number as the website stores them ('' if it is not one). */
const normalize = (v) => {
    const d = V.normalizePhone(v);
    return /^\d{10}$/.test(d) ? d : '';
};

/** A live (not deleted) customer who has this number as any of their numbers, or null. */
async function findByNumber(raw) {
    const n = normalize(raw);
    if (!n) return null;
    const direct = await Customer().findOne({ ...notDeleted, $or: PHONE_FIELDS.map((f) => ({ [f]: n })) }).lean();
    if (direct) return direct;
    const viaProfile = await Profile().findOne({ 'contacts.number': n }).select('customerId').lean();
    return viaProfile ? Customer().findOne({ _id: viaProfile.customerId, ...notDeleted }).lean() : null;
}

/** The website's rule: the highest serial among customers that are not deleted, plus one (and never one already in use). */
async function nextSerial() {
    const C = Customer();
    const top = await C.findOne({ sl_no: { $exists: true, $ne: null }, ...notDeleted }).sort({ sl_no: -1 }).select('sl_no').lean();
    let n = top && Number(top.sl_no) > 0 ? Number(top.sl_no) + 1 : 1;
    while (await C.exists({ sl_no: n, ...notDeleted })) n += 1;
    return n;
}

/** LGP + yymmdd + 3 hex, unique among the app's profiles (the format the website uses for customer ids). */
async function newCustomerCode() {
    const d = new Date();
    const ymd = `${String(d.getFullYear()).slice(2)}${String(d.getMonth() + 1).padStart(2, '0')}${String(d.getDate()).padStart(2, '0')}`;
    for (let i = 0; i < 20; i++) {
        const code = `LGP${ymd}${crypto.randomBytes(2).toString('hex').toUpperCase().slice(0, 3)}`;
        if (!(await Profile().exists({ customerCode: code }))) return code;
    }
    return `LGP${ymd}${crypto.randomBytes(3).toString('hex').toUpperCase()}`;
}

/** The app's side of a customer (code, branch, wishlist, bookings), made the first time it is needed. */
async function ensureProfile(customer, by = {}) {
    const P = Profile();
    const have = await P.findOne({ customerId: customer._id });
    if (have) return have;
    const contacts = [];
    const seen = new Set();
    for (const f of PHONE_FIELDS) {
        const n = normalize(customer[f]);
        if (n && !seen.has(n)) { seen.add(n); contacts.push({ number: n, label: f === 'whatsapp_no' ? 'whatsapp' : 'mobile' }); }
    }
    return P.create({
        customerId: customer._id, customerCode: await newCustomerCode(), contacts,
        branchId: by.branchId || 'main', branchName: by.branchName || 'Main branch',
        source: 'app', createdBy: by.id, createdByName: by.name,
    });
}

/**
 * The customer with this number, made the website's way if there is none. An existing customer is returned AS THEY ARE:
 * nothing of theirs is changed by a booking, a wishlist entry or a sale.
 * @param {{name?:string, mobile:string, address?:string}} p
 * @param {{id?:string, name?:string, branchId?:string, branchName?:string}} by  who is doing it (the signed-in person)
 * @returns {Promise<{customer:object, created:boolean}>}
 */
async function findOrCreate(p, by = {}) {
    const existing = await findByNumber(p.mobile);
    if (existing) return { customer: existing, created: false };
    const n = normalize(p.mobile);
    if (!n) throw Object.assign(new Error('Enter a valid 10-digit mobile number'), { statusCode: 400 });
    const now = new Date();
    const doc = await Customer().create({
        customer_name: String(p.name || '').trim() || 'Customer',
        customer_name_bengali: '',
        address: String(p.address || '').trim(),
        address_bengali: '',
        whatsapp_no: n,
        mobile_no: '',
        notification_type: 'all',
        created_by: by.id,
        created_by_name: by.name,
        created_at: now,
        updated_at: now,
        sl_no: await nextSerial(),
        is_deleted: false,
        source: 'app',
    });
    const customer = doc.toObject();
    await ensureProfile(customer, by);
    return { customer, created: true };
}

// ── wishlist and bookings: the app's own extras, kept on the profile (never on the website's customer record) ──

async function addToWishlist(customer, itemId, by = {}) {
    const profile = await ensureProfile(customer, by);
    const hit = (profile.wishlist || []).find((w) => String(w.item) === String(itemId));
    if (!hit) profile.wishlist.push({ item: itemId, status: 'active' });
    else if (hit.status === 'removed') { hit.status = 'active'; hit.addedAt = new Date(); }
    await profile.save();
    return profile;
}

async function removeFromWishlist(customer, itemId) {
    const profile = await Profile().findOne({ customerId: customer._id });
    const hit = profile && (profile.wishlist || []).find((w) => String(w.item) === String(itemId));
    if (hit) { hit.status = 'removed'; await profile.save(); }
}

async function addBooking(customer, bookingId, by = {}) {
    const profile = await ensureProfile(customer, by);
    profile.bookings.push(bookingId);
    await profile.save();
}

/** Customers with this piece on their wishlist: [{customer, addedAt}] */
async function wishlistedBy(itemId) {
    const profiles = await Profile().find({ wishlist: { $elemMatch: { item: itemId, status: 'active' } } }).lean();
    if (!profiles.length) return [];
    const customers = await Customer().find({ _id: { $in: profiles.map((p) => p.customerId) }, ...notDeleted }).lean();
    const byId = new Map(customers.map((c) => [String(c._id), c]));
    return profiles.filter((p) => byId.has(String(p.customerId))).map((p) => ({
        customer: byId.get(String(p.customerId)),
        addedAt: (p.wishlist.find((w) => String(w.item) === String(itemId) && w.status === 'active') || {}).addedAt,
    }));
}

const byIds = (ids) => Customer().find({ _id: { $in: ids } }).lean();

/** How the app has always shown a customer in its wishlist / booking lists. */
const display = (c) => ({ name: c.customer_name || '', mobile: c.whatsapp_no || c.mobile_no || '', address: c.address || '' });

module.exports = { normalize, findByNumber, nextSerial, newCustomerCode, ensureProfile, findOrCreate, addToWishlist, removeFromWishlist, addBooking, wishlistedBy, byIds, display, PHONE_FIELDS };
