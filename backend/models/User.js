/**
 * User.js - ONE list of people for the phone app AND the website (the `users` collection of the website's database).
 *
 * The website (PHP, in use for 1.5 years) owns this collection's shape, so its field names are the stored names and are
 * never changed: username, email, password, full_name, role, contact, address, profile_image, is_active, status,
 * created_at, last_login, ... The app adds its own fields on top (mobile, branchId, branchName, permissionOverrides,
 * language, fcmTokens, legacyAppIds); the website simply ignores them.
 *
 * The rest of the app keeps using the names it always had (user.name, user.isActive, user.profileImage ...): they are
 * aliases of the stored fields, so there is one value, not two copies that could drift apart. Deactivating someone on
 * the website switches them off in the app, and the other way round.
 *
 * One password serves both: the website writes PHP password_hash() ($2y$) values, the app bcryptjs ($2a$); both libraries
 * verify both (tested in scripts/user-model.test.js).
 *
 * Indexes are NOT created automatically here (autoIndex off): this collection belongs to a live website. The merge /
 * migration script creates the one the app needs (mobile, unique, sparse).
 */
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const ROLES = ['admin', 'owner', 'manager', 'staff', 'viewer', 'user'];

const userSchema = new mongoose.Schema({
    // ── the website's own fields ──────────────────────────────────────────────────────────────────────────────────
    username: { type: String, trim: true },
    email: { type: String, trim: true, default: '' },
    password: {
        type: String,
        required: [true, 'Password is required'],
        minlength: 6,
        select: false
    },
    full_name: {
        type: String,
        required: [true, 'Name is required'],
        trim: true,
        alias: 'name'
    },
    // The website stores 'admin', 'Admin', 'user' ...: reading always gives lower case, so 'Admin' still means admin.
    role: {
        type: String,
        default: 'staff',
        required: true,
        lowercase: true,
        // a custom check, not `enum`: the stored text may be 'Admin' (as the website wrote it) and must still save
        validate: { validator: (v) => ROLES.includes(String(v).toLowerCase()), message: (p) => `${p.value} is not a valid role` },
        get: (v) => (v == null ? v : String(v).toLowerCase())
    },
    contact: { type: String, trim: true, default: '' },
    address: { type: String, trim: true, default: '' },
    profile_image: { type: String, default: '', alias: 'profileImage' },
    is_active: { type: Boolean, default: true, alias: 'isActive' },
    status: { type: String, default: 'active' },
    last_login: { type: Date, default: null },
    last_login_ist: { type: String, default: '' },
    created_at: { type: Date, default: Date.now, alias: 'createdAt' },
    created_ist: { type: String, default: '' },
    // ── what the app adds ─────────────────────────────────────────────────────────────────────────────────────────
    // The number the person signs in with in the app (the website signs in with username / email).
    mobile: { type: String, trim: true },
    // Where the record was first made: 'website', 'app', or 'merge' (an app person matched to a website person).
    source: { type: String, default: undefined },
    // Explicit per-user permission overrides (only ever populated for manager/staff/viewer accounts; admin/owner always
    // bypass every check). Sparse: only keys that differ from the role's default grid (config/permissions.js).
    // Plain Mixed object, not a Map: every permission key is dot-namespaced (e.g. "items.delete").
    permissionOverrides: { type: mongoose.Schema.Types.Mixed, default: {} },
    language: { type: String, enum: ['en', 'bn'], default: 'en' },
    // The shop this person works at: new records are filed under it (utils/branches.js). 'main' = the built-in default.
    branchId: { type: String, default: 'main' },
    branchName: { type: String, default: 'Main branch' },
    // Push notification device tokens (one account can have several phones)
    fcmTokens: [{
        token: { type: String, required: true },
        platform: { type: String, default: 'android' },
        updatedAt: { type: Date, default: Date.now }
    }],
    // When the app's own list of people was merged into this one, a person's old app id was kept here, so a phone that
    // is still signed in with an old token (and old records that name the old id) can still be matched to them.
    legacyAppIds: { type: [String], default: undefined },
    updated_at: { type: Date, default: Date.now, alias: 'updatedAt' }
}, {
    collection: 'users',
    // queries written with the app's names (isActive, name ...) are turned into the stored website fields
    translateAliases: true,
    autoIndex: false,
    autoCreate: false,
    toObject: { getters: true },
});

// ======================
// METHODS
// ======================

// Hash password before saving (only when it was just set or changed)
userSchema.pre('save', async function (next) {
    if (!this.isModified('password')) {
        return next();
    }
    const salt = await bcrypt.genSalt(10);
    this.password = await bcrypt.hash(this.password, salt);
    this.updated_at = new Date();
    next();
});

userSchema.methods.comparePassword = async function (candidatePassword) {
    return await bcrypt.compare(candidatePassword, this.password);
};


// ======================
// STATICS
// ======================

/** 'YYYY-MM-DD HH:mm:ss' in India time: the text the website keeps next to its dates (created_ist, last_login_ist). */
const istText = (d = new Date()) => new Intl.DateTimeFormat('sv-SE', {
    timeZone: 'Asia/Kolkata', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
}).format(d);
userSchema.statics.istText = istText;

/**
 * Everything the website expects to find on a person, filled in for someone made in the app, so the website's own
 * pages and login treat them like anyone it made itself (they can sign in there with their username and the same password).
 */
userSchema.statics.forCreate = function forCreate(b) {
    const mobile = String(b.mobile || '').trim();
    return {
        username: String(b.username || mobile).trim(),
        email: String(b.email || '').trim(),
        password: b.password,
        full_name: b.name,
        role: b.role || 'staff',
        contact: String(b.contact || mobile).trim(),
        address: String(b.address || '').trim(),
        profile_image: b.profileImage || '',
        is_active: true,
        status: 'active',
        created_at: new Date(),
        created_ist: istText(),
        mobile: mobile || undefined,
        language: b.language,
        branchId: b.branchId,
        branchName: b.branchName,
        source: 'app',
    };
};

/** Sign in with a mobile number (the app), or a username / e-mail (the website's way): checked in that order. */
userSchema.statics.findByLogin = async function findByLogin(login, withPassword = false) {
    const id = String(login || '').trim();
    if (!id) return null;
    const pick = (q) => (withPassword ? this.findOne(q).select('+password') : this.findOne(q));
    const hit = (await pick({ mobile: id })) || (await pick({ username: id })) || (await pick({ email: { $in: [id, id.toLowerCase()] } }));
    if (hit) return hit;
    // website-only staff keep their phone in `contact` (no app `mobile` yet): accept it, but only when it names exactly one person
    const ten = id.replace(/\D/g, '').slice(-10);
    if (ten.length === 10 && /^[\d\s+().-]+$/.test(id)) {
        const same = await this.find({ contact: { $regex: `${ten}$` } }).select('_id').limit(2).lean();
        if (same.length === 1) return pick({ _id: same[0]._id });
    }
    return null;
};

/** Which of mobile / username / e-mail is already used by another person ('' if none): the website enforces the same. */
userSchema.statics.taken = async function taken({ mobile, username, email }, exceptId) {
    const not = exceptId ? { _id: { $ne: exceptId } } : {};
    if (mobile && (await this.exists({ mobile, ...not }))) return 'mobile number';
    if (username && (await this.exists({ username, ...not }))) return 'username';
    if (email && (await this.exists({ email: { $in: [email, String(email).toLowerCase()] }, ...not }))) return 'e-mail address';
    return '';
};

/** The shape the app, the portal and the API have always received (plus the website's own fields). Never the password. */
userSchema.methods.toJSON = function () {
    const o = this.toObject({ getters: false, virtuals: false });
    delete o.password;
    return {
        ...o,
        role: this.role,
        name: o.full_name,
        mobile: o.mobile || (/^\d{10,}$/.test(String(o.contact || '').replace(/\D/g, '')) ? String(o.contact).replace(/\D/g, '').slice(-10) : ''),
        isActive: o.is_active !== false,
        profileImage: o.profile_image || null,
        createdAt: o.created_at,
        updatedAt: o.updated_at || o.created_at,
    };
};

const User = mongoose.models.User || mongoose.model('User', userSchema);
module.exports = User;
module.exports.ROLES = ROLES;
