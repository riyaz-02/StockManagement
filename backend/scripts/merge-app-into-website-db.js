/**
 * merge-app-into-website-db.js - bring the app's database into the website's database, so the phone app and the website
 * work on ONE set of records. The website's structure is the master; the app adapts (see docs/DB_UNIFICATION.md).
 *
 *   node scripts/merge-app-into-website-db.js <source uri/db> <target uri/db> [--apply] [--roles website|app|higher]
 *                                             [--report file.json] [--allow-remote]
 *
 *   source = the app's old database (e.g. jewellery_stock): only ever READ.
 *   target = the website's database (e.g. shopmanage): only ever receives INSERTS, plus the app's extra fields added to people.
 *
 * What it does (nothing is written without --apply; without it you get a plan, and a report you can read and approve):
 *   1. Copies every app collection into the target under the same name (sales -> app_sales, settings -> app_settings,
 *      because the website has its own `sales` / `settings`). Insert only: a document whose _id is already there is left alone.
 *      Indexes are copied too. A copy never goes into a collection the website uses for something else.
 *   2. People: each app user is matched to a website user by phone number (the website's `contact`). A match keeps the
 *      WEBSITE's record, name, password and role untouched and only gets the app's extra fields added (mobile, branch,
 *      permission overrides, language, device tokens, and the old app id in legacyAppIds). A person with no match is added
 *      in the website's own format, with the same _id and the same password hash. A phone number shared by two website
 *      users is NOT guessed: it is listed for a person to decide.
 *   3. Customers: the app's own small customer list is folded into the website's customers. Someone whose number the
 *      website already has is the same customer (their wishlist and bookings move onto the app's profile for that
 *      customer, and the bookings / sales that named the old id are pointed at the website's customer). Someone new is
 *      added exactly as the website's "add customer" page adds one (next serial, is_deleted:false ...).
 *   Safe to run again: it only ever adds what is missing.
 */
'use strict';
const fs = require('fs');
const crypto = require('crypto');
const { MongoClient, BSON } = require('mongoose').mongo;
const { describeUri } = require('../services/dbBackup');

const RENAMES = { settings: 'app_settings' };
// the app no longer keeps these (one collection per operation, docs/DB_UNIFICATION.md): not copied. If one holds documents
// they are listed as a problem, to be converted by hand first. `sales` was the quick-sell record (a sale is an invoice),
// the others were replaced by the website's own: gst_data (filed returns), outputDoc (generated GST records), purchases.
const RETIRED = new Set(['sales', 'app_sales', 'app_gst_filings', 'app_gst_documents', 'app_stock_entries', 'stockentries', 'app_legacy_invoices', 'app_purchases']);
// collections the website uses for its own things: nothing from the app may land in them
const WEBSITE_ONLY = new Set(['daily_snapshots', 'gst_data', 'inventory', 'newyear_invite_2026', 'outputDoc', 'sales', 'settings', 'shop_info', 'stock_log', 'temp_customer_uploads', 'wastage_reports', 'suppliers']);
const SPECIAL = new Set(['users', 'customers']);          // merged record by record, not copied
const ROLE_RANK = { user: 0, viewer: 1, staff: 2, manager: 3, owner: 4, admin: 5 };
const PHONE_FIELDS = ['whatsapp_no', 'mobile_no', 'mobile_no_3', 'mobile_no_4'];

const phoneOf = (v) => {
    const d = String(v == null ? '' : v).replace(/\D/g, '');
    return d.length >= 10 ? d.slice(-10) : '';
};
const istText = (d = new Date()) => new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Kolkata', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false }).format(d);
const isLocal = (uri) => /^(127\.0\.0\.1|localhost)(:|$)/.test(describeUri(uri).host);

async function missingIds(coll, ids) {
    if (!ids.length) return [];
    const have = new Set((await coll.find({ _id: { $in: ids } }, { projection: { _id: 1 } }).toArray()).map((d) => String(d._id)));
    return ids.filter((id) => !have.has(String(id)));
}

// ── 1. plain collections ─────────────────────────────────────────────────────────────────────────────────────────
async function copyCollections(sdb, tdb, apply, report) {
    const list = (await sdb.listCollections({}, { nameOnly: false }).toArray()).filter((c) => !c.name.startsWith('system.') && c.type !== 'view');
    for (const c of list) {
        if (SPECIAL.has(c.name)) continue;
        const targetName = RENAMES[c.name] || c.name;
        const row = { from: c.name, to: targetName, inSource: 0, alreadyInTarget: 0, added: 0, indexesAdded: 0, indexProblems: [] };
        if (RETIRED.has(c.name)) {
            // not part of the one database: never copied (an empty one is simply ignored)
            const n = await sdb.collection(c.name).estimatedDocumentCount();
            if (n) {
                row.retired = true; row.inSource = n; row.to = '(not copied)';
                row.problem = `"${c.name}" holds ${n} document(s) but the app no longer uses that collection: convert them first (docs/DB_UNIFICATION.md)`;
                report.problems.push(row.problem);
                report.collections.push(row);
            }
            continue;
        }
        report.collections.push(row);
        if (WEBSITE_ONLY.has(targetName)) { row.problem = `refused: "${targetName}" is a collection the website uses for something else`; report.problems.push(row.problem); continue; }
        const src = sdb.collection(c.name);
        const dst = tdb.collection(targetName);
        row.inSource = await src.estimatedDocumentCount();
        let batch = [];
        const flush = async () => {
            if (!batch.length) return;
            const ids = batch.map((d) => d._id);
            const need = new Set((await missingIds(dst, ids)).map(String));
            row.alreadyInTarget += ids.length - need.size;
            const fresh = batch.filter((d) => need.has(String(d._id)));
            let skipped = 0;
            if (fresh.length && apply) {
                try { await dst.insertMany(fresh, { ordered: false }); } catch (e) {
                    // a document whose unique key (not its _id) is already in the target is the same record under another id: leave it
                    const errs = e.writeErrors || [];
                    if (e.code !== 11000 || !errs.length || errs.some((w) => w.code !== 11000)) throw e;
                    skipped = errs.length;
                    (row.duplicateKeySkipped = row.duplicateKeySkipped || []).push(...errs.map((w) => String(fresh[w.index] && fresh[w.index]._id)));
                }
            }
            row.added += fresh.length - skipped;
            batch = [];
        };
        for await (const buf of src.find({}, { raw: true, batchSize: 500 })) {
            batch.push(BSON.deserialize(buf, { promoteValues: false, promoteBuffers: false, promoteLongs: false }));
            if (batch.length >= 500) await flush();
        }
        await flush();
        const have = new Set((await dst.indexes().catch(() => [])).map((i) => i.name));
        for (const ix of (await src.indexes().catch(() => [])).filter((i) => i.name !== '_id_' && !have.has(i.name))) {
            const { key, name, v, ns, ...opts } = ix;
            if (!apply) { row.indexesAdded += 1; continue; }
            try { await dst.createIndex(key, { name, ...opts }); row.indexesAdded += 1; } catch (e) { row.indexProblems.push(`${name}: ${e.message}`); }
        }
    }
}

// ── 2. people ────────────────────────────────────────────────────────────────────────────────────────────────────
async function mergeUsers(sdb, tdb, apply, rolePolicy, report) {
    const res = report.users = { appUsers: 0, matched: [], addedAsNew: [], alreadyMerged: 0, ambiguous: [], roleConflicts: [], activeConflicts: [], websiteOnly: 0 };
    if (!(await sdb.listCollections({ name: 'users' }).toArray()).length) return;
    const appUsers = await sdb.collection('users').find({}).toArray();
    const T = tdb.collection('users');
    const site = await T.find({}).toArray();
    res.appUsers = appUsers.length;
    const byPhone = new Map();
    const usernames = new Set(site.map((u) => String(u.username || '').toLowerCase()).filter(Boolean));
    for (const u of site) {
        for (const p of new Set([phoneOf(u.contact), phoneOf(u.mobile), phoneOf(u.username)].filter(Boolean))) {
            if (!byPhone.has(p)) byPhone.set(p, []);
            byPhone.get(p).push(u);
        }
    }
    const touched = new Set();
    for (const a of appUsers) {
        const id = String(a._id);
        const label = { appId: id, name: a.name, mobile: a.mobile };
        const done = site.find((u) => String(u._id) === id || (u.legacyAppIds || []).includes(id));
        if (done) { res.alreadyMerged += 1; touched.add(String(done._id)); continue; }
        const cands = (byPhone.get(phoneOf(a.mobile)) || []).filter((u, i, arr) => arr.findIndex((x) => String(x._id) === String(u._id)) === i);
        if (cands.length > 1) { res.ambiguous.push({ ...label, websiteUsers: cands.map((u) => ({ id: String(u._id), username: u.username, name: u.full_name })) }); continue; }
        if (cands.length === 1) {
            const w = cands[0];
            touched.add(String(w._id));
            const set = { source: w.source || 'merge' };
            const extras = { mobile: a.mobile, branchId: a.branchId, branchName: a.branchName, permissionOverrides: a.permissionOverrides, language: a.language };
            for (const [k, v] of Object.entries(extras)) if (v !== undefined && w[k] === undefined) set[k] = v;
            if (a.fcmTokens && a.fcmTokens.length && !w.fcmTokens) set.fcmTokens = a.fcmTokens;
            const wRole = String(w.role || '').toLowerCase();
            const aRole = String(a.role || '').toLowerCase();
            if (wRole !== aRole) {
                const keep = rolePolicy === 'app' ? aRole : rolePolicy === 'higher' ? ((ROLE_RANK[aRole] || 0) > (ROLE_RANK[wRole] || 0) ? aRole : wRole) : wRole;
                res.roleConflicts.push({ ...label, websiteUser: w.username, website: wRole, app: aRole, kept: keep });
                if (keep !== wRole) set.role = keep;
            }
            if ((a.isActive !== false) !== (w.is_active !== false)) res.activeConflicts.push({ ...label, websiteUser: w.username, websiteActive: w.is_active !== false, appActive: a.isActive !== false, kept: 'website' });
            res.matched.push({ ...label, websiteUser: w.username, websiteName: w.full_name, websiteId: String(w._id), willSet: Object.keys(set) });
            if (apply) await T.updateOne({ _id: w._id }, { $set: set, $addToSet: { legacyAppIds: id } });
            continue;
        }
        // not on the website: add them in the website's own format, same _id, same password hash
        let username = String(a.mobile || id);
        while (usernames.has(username.toLowerCase())) username += '_app';
        usernames.add(username.toLowerCase());
        const created = a.createdAt instanceof Date ? a.createdAt : new Date();
        const doc = {
            _id: a._id, username, email: '', password: a.password, full_name: a.name, role: a.role || 'staff', contact: a.mobile || '', address: '',
            profile_image: a.profileImage || '', is_active: a.isActive !== false, status: a.isActive === false ? 'inactive' : 'active', last_login: null,
            created_at: created, created_ist: istText(created), mobile: a.mobile, branchId: a.branchId || 'main', branchName: a.branchName || 'Main branch',
            permissionOverrides: a.permissionOverrides || {}, language: a.language || 'en', source: 'merge',
        };
        if (a.fcmTokens && a.fcmTokens.length) doc.fcmTokens = a.fcmTokens;
        res.addedAsNew.push({ ...label, username });
        if (apply) await T.insertOne(doc);
    }
    res.websiteOnly = site.filter((u) => !touched.has(String(u._id)) && !u.mobile).length;
    if (apply) {
        try { await T.createIndex({ mobile: 1 }, { name: 'mobile_1', unique: true, sparse: true }); } catch (e) { report.problems.push(`users.mobile unique index: ${e.message}`); }
    }
}

// ── 3. customers ─────────────────────────────────────────────────────────────────────────────────────────────────
async function mergeCustomers(sdb, tdb, apply, report) {
    const res = report.customers = { appCustomers: 0, sameAsWebsite: [], addedAsNew: [], bookingsRepointed: 0, salesRepointed: 0, skipped: [] };
    if (!(await sdb.listCollections({ name: 'customers' }).toArray()).length) return;
    const legacy = await sdb.collection('customers').find({}).toArray();
    res.appCustomers = legacy.length;
    if (!legacy.length) return;
    const C = tdb.collection('customers');
    const P = tdb.collection('app_customer_profiles');
    const live = await C.find({ is_deleted: { $ne: true } }).toArray();
    const byPhone = new Map();
    for (const c of live) for (const f of PHONE_FIELDS) { const p = phoneOf(c[f]); if (p && !byPhone.has(p)) byPhone.set(p, c); }
    for (const pr of await P.find({}, { projection: { customerId: 1, contacts: 1 } }).toArray()) {
        for (const k of pr.contacts || []) { const p = phoneOf(k.number); const cust = live.find((c) => String(c._id) === String(pr.customerId)); if (p && cust && !byPhone.has(p)) byPhone.set(p, cust); }
    }
    let serial = live.reduce((m, c) => Math.max(m, Number(c.sl_no) || 0), 0);
    const codes = new Set((await P.find({}, { projection: { customerCode: 1 } }).toArray()).map((p) => p.customerCode));
    const newCode = () => {
        const d = new Date();
        const ymd = `${String(d.getFullYear()).slice(2)}${String(d.getMonth() + 1).padStart(2, '0')}${String(d.getDate()).padStart(2, '0')}`;
        for (let i = 0; i < 50; i++) { const code = `LGP${ymd}${crypto.randomBytes(2).toString('hex').toUpperCase().slice(0, 3)}`; if (!codes.has(code)) { codes.add(code); return code; } }
        const code = `LGP${ymd}${crypto.randomBytes(3).toString('hex').toUpperCase()}`; codes.add(code); return code;
    };
    for (const l of legacy) {
        const phone = phoneOf(l.mobile);
        let target = (await C.findOne({ _id: l._id })) || (phone ? byPhone.get(phone) : null);
        const label = { appCustomerId: String(l._id), name: l.name, mobile: l.mobile };
        let created = false;
        if (!target) {
            if (!phone) { res.skipped.push({ ...label, why: 'no valid 10-digit number to match or create from' }); continue; }
            serial += 1;
            const now = l.createdAt instanceof Date ? l.createdAt : new Date();
            target = {
                _id: l._id, customer_name: String(l.name || '').trim() || 'Customer', customer_name_bengali: '', address: String(l.address || '').trim(), address_bengali: '',
                whatsapp_no: phone, mobile_no: '', notification_type: 'all', created_by: 'merge', created_by_name: 'merge from the app', created_at: now, updated_at: now,
                sl_no: serial, is_deleted: false, source: 'merge',
            };
            created = true;
            res.addedAsNew.push({ ...label, serial });
            if (apply) await C.insertOne(target);
            byPhone.set(phone, target);
        } else if (String(target._id) !== String(l._id)) {
            res.sameAsWebsite.push({ ...label, websiteCustomerId: String(target._id), websiteName: target.customer_name, serial: target.sl_no });
        } else {
            continue; // this very customer was merged on an earlier run
        }
        // the app's side: wishlist and bookings on the profile
        const wishlist = (l.wishlist || []).map((w) => ({ item: w.item, addedAt: w.addedAt || new Date(), status: w.status || 'active' }));
        const bookings = l.bookings || [];
        if (apply && (wishlist.length || bookings.length || created)) {
            let prof = await P.findOne({ customerId: target._id });
            if (!prof) {
                const contacts = PHONE_FIELDS.map((f) => phoneOf(target[f])).filter((v, i, a) => v && a.indexOf(v) === i).map((n, i) => ({ number: n, label: i === 0 ? 'whatsapp' : 'mobile' }));
                await P.insertOne({ customerId: target._id, customerCode: newCode(), contacts, branchId: 'main', branchName: 'Main branch', wishlist: [], bookings: [], source: 'merge', createdBy: 'merge', createdByName: 'merge from the app', createdAt: new Date(), updatedAt: new Date() });
                prof = await P.findOne({ customerId: target._id });
            }
            const have = new Set((prof.wishlist || []).map((w) => String(w.item)));
            const add = wishlist.filter((w) => !have.has(String(w.item)));
            const haveB = new Set((prof.bookings || []).map(String));
            const addB = bookings.filter((b) => !haveB.has(String(b)));
            if (add.length || addB.length) await P.updateOne({ _id: prof._id }, { $push: { ...(add.length ? { wishlist: { $each: add } } : {}), ...(addB.length ? { bookings: { $each: addB } } : {}) } });
        }
        // bookings and sales that named the old customer id now name the website's customer
        if (String(target._id) !== String(l._id)) {
            for (const [coll, key] of [['bookings', 'bookingsRepointed']]) {
                // a plan reads the app's own collections (the copies do not exist yet); a real run reads the copies it has just made
                const from = apply ? tdb.collection(coll) : sdb.collection(coll);
                const n = await from.countDocuments({ customerId: l._id });
                res[key] += n;
                if (apply && n) await tdb.collection(coll).updateMany({ customerId: l._id }, { $set: { customerId: target._id } });
            }
        }
    }
}

// ── the whole thing ──────────────────────────────────────────────────────────────────────────────────────────────
async function merge({ sourceUri, sourceDb, targetUri, targetDb, apply = false, roles = 'website', log = () => {} }) {
    if (sourceUri === targetUri && sourceDb === targetDb) throw new Error('The source and the target are the same database.');
    const report = { startedAt: new Date().toISOString(), mode: apply ? 'APPLIED' : 'PLAN ONLY (nothing written)', source: `${describeUri(sourceUri).host}/${sourceDb}`, target: `${describeUri(targetUri).host}/${targetDb}`, rolePolicy: roles, problems: [], collections: [] };
    const sc = new MongoClient(sourceUri, { serverSelectionTimeoutMS: 15000, appName: 'lgp-merge' });
    const tc = sourceUri === targetUri ? sc : new MongoClient(targetUri, { serverSelectionTimeoutMS: 15000, appName: 'lgp-merge' });
    await sc.connect();
    if (tc !== sc) await tc.connect();
    try {
        const sdb = sc.db(sourceDb);
        const tdb = tc.db(targetDb);
        log('copying collections ...');
        await copyCollections(sdb, tdb, apply, report);
        log('merging people ...');
        await mergeUsers(sdb, tdb, apply, roles, report);
        log('merging customers ...');
        await mergeCustomers(sdb, tdb, apply, report);
    } finally {
        await sc.close().catch(() => {});
        if (tc !== sc) await tc.close().catch(() => {});
    }
    report.finishedAt = new Date().toISOString();
    return report;
}

module.exports = { merge, phoneOf, RENAMES, WEBSITE_ONLY };

if (require.main === module) {
    (async () => {
        const args = process.argv.slice(2);
        const take = (n) => { const i = args.indexOf(n); return i >= 0 ? args.splice(i, 2)[1] : ''; };
        const apply = args.includes('--apply'); if (apply) args.splice(args.indexOf('--apply'), 1);
        const allowRemote = args.includes('--allow-remote'); if (allowRemote) args.splice(args.indexOf('--allow-remote'), 1);
        const roles = take('--roles') || 'website';
        const reportFile = take('--report');
        const [source, target] = args;
        if (!source || !target || !['website', 'app', 'higher'].includes(roles)) {
            console.log('Usage: node scripts/merge-app-into-website-db.js <source uri/db> <target uri/db> [--apply] [--roles website|app|higher] [--report file.json] [--allow-remote]');
            process.exit(1);
        }
        const s = describeUri(source);
        const t = describeUri(target);
        if (!s.defaultDb || !t.defaultDb) { console.error('Both addresses must end with the database name (...mongodb.net/<database>).'); process.exit(1); }
        if (apply && !isLocal(target) && !allowRemote) { console.error('Refusing to WRITE to a database that is not on this computer. If you really mean it, add --allow-remote (after a backup, a rehearsal and a plan you have read).'); process.exit(1); }
        const report = await merge({ sourceUri: source, sourceDb: s.defaultDb, targetUri: target, targetDb: t.defaultDb, apply, roles, log: console.log });
        if (reportFile) fs.writeFileSync(reportFile, JSON.stringify(report, null, 2));
        console.log(`\n${report.mode}\nsource ${report.source}  ->  target ${report.target}`);
        console.table(report.collections.map((c) => ({ from: c.from, to: c.to, 'in source': c.inSource, 'already there': c.alreadyInTarget, [apply ? 'added' : 'would add']: c.added, 'indexes': c.indexesAdded })));
        const u = report.users;
        console.log(`People: ${u.appUsers} in the app | matched to a website person: ${u.matched.length} | added as new: ${u.addedAsNew.length} | already merged: ${u.alreadyMerged} | needs a decision (shared number): ${u.ambiguous.length} | website people without an app number: ${u.websiteOnly}`);
        if (u.roleConflicts.length) console.log(`  role differs for ${u.roleConflicts.length} matched person(s) (kept: ${roles}): ${u.roleConflicts.map((r) => `${r.name} website=${r.website} app=${r.app}`).join('; ')}`);
        const c = report.customers;
        console.log(`Customers: ${c.appCustomers} in the app | same as a website customer: ${c.sameAsWebsite.length} | added as new: ${c.addedAsNew.length} | skipped: ${c.skipped.length} | bookings repointed: ${c.bookingsRepointed} | sales repointed: ${c.salesRepointed}`);
        if (report.problems.length) console.log('PROBLEMS:\n  ' + report.problems.join('\n  '));
        if (!apply) console.log('\nThis was only a plan. Nothing was written.');
    })().catch((e) => { console.error('Stopped:', e.message); process.exit(1); });
}
