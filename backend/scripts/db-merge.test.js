// The merge of the app's database into the website's, on throw-away LOCAL databases shaped like production.
// Run: node scripts/db-merge.test.js
// Proves: a plan changes nothing; a real run leaves every website record exactly as it was (a matched person only GAINS the app's
// extra fields); people and customers are matched by phone number; nothing is guessed when a number is shared; running it again
// changes nothing; the source is never touched; and the new models then work on the merged database.
'use strict';
require('dotenv').config();
const assert = require('assert');
const { execFileSync } = require('child_process');
const crypto = require('crypto');
const { MongoClient, ObjectId } = require('mongoose').mongo;
const mongoose = require('mongoose');
const { merge } = require('./merge-app-into-website-db');

const m = /^(mongodb:\/\/(?:127\.0\.0\.1|localhost)(?::\d+)?)/.exec(process.env.MONGODB_URI || '');
assert(m, 'refusing to run: MONGODB_URI is not a local database');
const BASE = m[1];
const tag = `${Date.now()}`;
const SITE = `mg_site_${tag}`;
const APP = `mg_app_${tag}`;
const ok = (n) => console.log('ok -', n);
const phpHash = (pw) => execFileSync('php', ['-r', 'echo password_hash($argv[1], PASSWORD_DEFAULT);', '--', pw]).toString();

const dump = async (db, names) => {
    const out = {};
    for (const n of names) out[n] = (await db.collection(n).find({}, { raw: true, sort: { _id: 1 } }).toArray()).map((b) => b.toString('base64'));
    return out;
};
const allNames = async (db) => (await db.listCollections().toArray()).map((c) => c.name).filter((n) => !n.startsWith('system.')).sort();
const fingerprint = async (db) => crypto.createHash('sha256').update(JSON.stringify(await dump(db, await allNames(db)))).digest('hex');
const oid = () => new ObjectId();
const APP_FIELDS = ['mobile', 'branchId', 'branchName', 'permissionOverrides', 'language', 'fcmTokens', 'legacyAppIds', 'source'];

(async () => {
    const client = new MongoClient(BASE, { serverSelectionTimeoutMS: 8000 });
    await client.connect();
    const site = client.db(SITE);
    const app = client.db(APP);
    try {
        // ───────────── the website's database, as the PHP site has been filling it ─────────────
        const siteHash = phpHash('Site@Pass1');
        const t0 = new Date('2025-04-01T05:00:00Z');
        const W = { w1: oid(), w2: oid(), w3: oid(), w4: oid() };
        await site.collection('customers').insertMany([
            { _id: W.w1, customer_name: 'Anita Roy', customer_name_bengali: 'অনিতা', address: 'Kolkata', whatsapp_no: '9830000001', mobile_no: '9830000002', notification_type: 'all', created_at: t0, sl_no: 1, is_deleted: false },
            { _id: W.w2, customer_name: 'Bimal Das', address: 'Howrah', whatsapp_no: '9830000003', mobile_no: '', mobile_no_3: '9830000009', created_at: t0, sl_no: 2, is_deleted: false },
            { _id: W.w3, customer_name: 'Deleted Person', whatsapp_no: '9830000004', created_at: t0, sl_no: 3, is_deleted: true },
            { _id: W.w4, customer_name: 'Chitra Sen', whatsapp_no: '9830000005', mobile_no: '9830000006', created_at: t0, sl_no: 4, is_deleted: false },
        ]);
        const U = { raju: oid(), sita: oid(), twin1: oid(), twin2: oid(), plain: oid() };
        await site.collection('users').insertMany([
            { _id: U.raju, username: 'raju', email: 'raju@shop.example', password: siteHash, full_name: 'Raju Das', role: 'Admin', contact: '9830011111', address: 'K', profile_image: '', created_at: t0, is_active: true, status: 'active', remember_token: 'keep-me' },
            { _id: U.sita, username: 'sita', email: 'sita@shop.example', password: siteHash, full_name: 'Sita Roy', role: 'staff', contact: '+91 98300 22222', created_at: t0, is_active: true, status: 'active' },
            { _id: U.twin1, username: 'twin1', email: 't1@x', password: siteHash, full_name: 'Twin One', role: 'staff', contact: '9830033333', created_at: t0, is_active: true },
            { _id: U.twin2, username: 'twin2', email: 't2@x', password: siteHash, full_name: 'Twin Two', role: 'staff', contact: '9830033333', created_at: t0, is_active: true },
            { _id: U.plain, username: 'plain', email: 'p@x', password: siteHash, full_name: 'No Phone', role: 'user', contact: '', created_at: t0, is_active: true },
        ]);
        await site.collection('invoices').insertMany([{ invoice_number: '1001', customer_name: 'Anita Roy', total_payable_amount: 5000 }, { invoice_number: '1002', customer_name: 'Bimal Das', total_payable_amount: 7000 }]);
        await site.collection('shop_info').insertOne({ gstin: '19ABCDE1234F1Z5', invoice_counter: 1002 });
        await site.collection('sales').insertMany([{ website_sale: 1 }, { website_sale: 2 }]);
        await site.collection('settings').insertOne({ website_setting: 'theme', value: 'gold' });
        await site.collection('customers').createIndex({ sl_no: 1 }, { name: 'sl_no_1' });

        // ───────────── the app's own database ─────────────
        const A = { a1: oid(), a2: oid(), a3: oid(), a4: oid(), a5: oid() };
        const appHash = phpHash('App@Pass2');
        await app.collection('users').insertMany([
            { _id: A.a1, name: 'Raju (app)', mobile: '9830011111', password: appHash, role: 'staff', branchId: 'BAG', branchName: 'Bagbazar', permissionOverrides: { 'items.delete': false }, language: 'bn', isActive: true, fcmTokens: [{ token: 'tok-1', platform: 'android' }], createdAt: t0 },
            { _id: A.a2, name: 'Sita (app)', mobile: '9830022222', password: appHash, role: 'staff', branchId: 'main', branchName: 'Main branch', language: 'en', isActive: true, createdAt: t0 },
            { _id: A.a3, name: 'Mumbai Manager', mobile: '9000000011', password: appHash, role: 'manager', branchId: 'MUM', branchName: 'Mumbai', language: 'en', isActive: true, createdAt: t0 },
            { _id: A.a4, name: 'Shared Number', mobile: '9830033333', password: appHash, role: 'staff', branchId: 'main', branchName: 'Main branch', isActive: true, createdAt: t0 },
            { _id: A.a5, name: 'Left The Shop', mobile: '9000000055', password: appHash, role: 'viewer', branchId: 'main', branchName: 'Main branch', isActive: false, createdAt: t0 },
        ]);
        await app.collection('users').createIndex({ mobile: 1 }, { unique: true, name: 'mobile_1' });
        const I = { i1: oid(), i2: oid() };
        const B = { b1: oid(), b2: oid() };
        const L = { l1: oid(), l2: oid(), l3: oid(), l4: oid() };
        await app.collection('customers').insertMany([
            { _id: L.l1, name: 'Chitra D', mobile: '9830000006', address: 'typed on a booking', wishlist: [{ item: I.i1, status: 'active', addedAt: t0 }], bookings: [B.b1], createdAt: t0 },
            { _id: L.l2, name: 'Anita R', mobile: '9830000002', wishlist: [{ item: I.i2, status: 'removed', addedAt: t0 }], bookings: [], createdAt: t0 },
            { _id: L.l3, name: 'Brand New', mobile: '9831112222', address: 'Salt Lake', wishlist: [{ item: I.i1, status: 'active', addedAt: t0 }], bookings: [B.b2], createdAt: t0 },
            { _id: L.l4, name: 'Bad Number', mobile: '12345', wishlist: [], bookings: [] },
        ]);
        await app.collection('items').insertMany([{ _id: I.i1, name: 'Gold Ring', barcode: 'B1', netWeight: 5 }, { _id: I.i2, name: 'Silver Chain', barcode: 'B2', netWeight: 20 }]);
        await app.collection('items').createIndex({ barcode: 1 }, { unique: true, name: 'barcode_1' });
        await app.collection('containers').insertOne({ name: 'Box A', slots: [] });
        await app.collection('bookings').insertMany([{ _id: B.b1, itemId: I.i1, customerId: L.l1, customerName: 'Chitra D', mobile: '9830000006' }, { _id: B.b2, itemId: I.i1, customerId: L.l3, customerName: 'Brand New', mobile: '9831112222' }]);
        await app.collection('sales').insertMany([{ itemId: I.i1, customerId: L.l1, amount: 100 }, { itemId: I.i2, customerId: L.l3, amount: 200 }]);
        await app.collection('settings').insertMany([{ category: 'tag', type: 'size', value: 'small' }, { category: 'tag', type: 'font', value: 'bold' }]);
        await app.collection('app_gst_settings').insertOne({ key: 'main', frequency: 'monthly' });

        const before = { site: await fingerprint(site), app: await fingerprint(app) };
        const siteKept = ['invoices', 'shop_info', 'sales', 'settings'];
        const siteBeforeDump = await dump(site, [...siteKept, 'customers', 'users']);
        const args = { sourceUri: `${BASE}/${APP}`, sourceDb: APP, targetUri: `${BASE}/${SITE}`, targetDb: SITE };

        // ── a plan changes nothing and says what it would do ──
        const plan = await merge({ ...args, apply: false });
        assert.strictEqual(await fingerprint(site), before.site, 'a plan leaves the website database untouched');
        assert.strictEqual(await fingerprint(app), before.app, 'a plan leaves the app database untouched');
        const row = (r, to) => r.collections.find((c) => c.to === to);
        assert.strictEqual(row(plan, 'items').added, 2);
        assert(!row(plan, 'app_sales') && plan.problems.some((x) => /"sales" holds 2 document/.test(x)), 'the retired quick-sell collection is not copied, and its 2 documents are reported');
        assert(row(plan, 'app_settings') && row(plan, 'app_settings').from === 'settings', 'the app\'s settings go to app_settings');
        assert(!plan.collections.some((c) => c.to === 'sales' || c.to === 'settings'), 'nothing is planned into the website\'s own sales / settings');
        assert.strictEqual(plan.users.matched.length, 2);
        assert.strictEqual(plan.users.addedAsNew.length, 2);
        assert.strictEqual(plan.users.ambiguous.length, 1);
        assert.strictEqual(plan.users.roleConflicts.length, 1);
        assert.strictEqual(plan.customers.sameAsWebsite.length, 2);
        assert.strictEqual(plan.customers.addedAsNew.length, 1);
        assert.strictEqual(plan.customers.skipped.length, 1);
        assert.strictEqual(plan.customers.bookingsRepointed, 1, 'the plan counts what it would repoint');
        ok('a plan changes nothing in either database, and reports exactly what a real run would do');

        // ── the real run ──
        const done = await merge({ ...args, apply: true });
        assert.strictEqual(done.problems.length, 1, 'the only problem is the retired quick-sell collection holding documents');
        assert(/"sales" holds 2 document/.test(done.problems[0]));

        const afterDump = await dump(site, siteKept);
        for (const n of siteKept) assert.deepStrictEqual(afterDump[n], siteBeforeDump[n], `the website's ${n} is byte-for-byte unchanged`);
        const custAfter = await site.collection('customers').find({}).toArray();
        const custBefore = siteBeforeDump.customers.length;
        assert.strictEqual(custAfter.filter((c) => [W.w1, W.w2, W.w3, W.w4].some((id) => id.equals(c._id))).length, 4);
        const rawNow = (await dump(site, ['customers'])).customers;
        for (const b64 of siteBeforeDump.customers) assert(rawNow.includes(b64), 'every existing website customer is byte-identical');
        assert.strictEqual(custAfter.length, custBefore + 1, 'exactly one customer was added');
        ok("the website's invoices, shop info, sales, settings and every existing customer are byte-for-byte unchanged");

        // people
        const users = Object.fromEntries((await site.collection('users').find({}).toArray()).map((u) => [String(u._id), u]));
        const strip = (u) => Object.fromEntries(Object.entries(u).filter(([k]) => !APP_FIELDS.includes(k)));
        const beforeUsers = Object.fromEntries((await Promise.all(Object.values(U).map((id) => site.collection('users').findOne({ _id: id })))).map((u) => [String(u._id), u]));
        const rajuBefore = JSON.parse(JSON.stringify(strip(users[String(U.raju)])));
        assert.strictEqual(rajuBefore.role, 'Admin', "the website's role text is untouched");
        assert.strictEqual(users[String(U.raju)].password, siteHash, "a matched person keeps the website's password");
        assert.strictEqual(users[String(U.raju)].full_name, 'Raju Das', "and the website's name");
        assert.strictEqual(users[String(U.raju)].mobile, '9830011111');
        assert.strictEqual(users[String(U.raju)].branchId, 'BAG');
        assert.deepStrictEqual(users[String(U.raju)].permissionOverrides, { 'items.delete': false });
        assert.deepStrictEqual(users[String(U.raju)].legacyAppIds, [String(A.a1)], 'the old app id is kept');
        assert.strictEqual(users[String(U.raju)].remember_token, 'keep-me');
        assert.deepStrictEqual(users[String(U.sita)].legacyAppIds, [String(A.a2)], "a number written as '+91 98300 22222' still matches");
        for (const k of ['twin1', 'twin2', 'plain']) assert.deepStrictEqual(users[String(U[k])], beforeUsers[String(U[k])], `${k} (not matched) is exactly as it was`);
        const added = await site.collection('users').findOne({ _id: A.a3 });
        assert(added && added.username === '9000000011' && added.full_name === 'Mumbai Manager' && added.role === 'manager' && added.email === '' && added.password === appHash && added.is_active === true && added.status === 'active' && added.source === 'merge' && added.branchId === 'MUM');
        const gone = await site.collection('users').findOne({ _id: A.a5 });
        assert(gone && gone.is_active === false && gone.status === 'inactive', 'an inactive app person stays inactive');
        assert(!(await site.collection('users').findOne({ _id: A.a4 })), 'a shared number is not guessed: nothing was added for it');
        assert.strictEqual(done.users.ambiguous[0].websiteUsers.length, 2, 'the two website people who share the number are listed for a decision');
        assert.strictEqual(done.users.roleConflicts[0].kept, 'admin', 'the website role wins');
        const ix = (await site.collection('users').indexes()).find((i) => i.name === 'mobile_1');
        assert(ix && ix.unique && ix.sparse, 'a unique, sparse index on mobile is made');
        ok('people: matched ones only GAIN the app fields (website name/password/role untouched), new ones are added in the website format, shared numbers are listed not guessed');

        // customers
        const w4 = await site.collection('customers').findOne({ _id: W.w4 });
        const prof4 = await site.collection('app_customer_profiles').findOne({ customerId: W.w4 });
        assert(prof4 && /^LGP\d{6}[0-9A-F]{3,6}$/.test(prof4.customerCode));
        assert.strictEqual(String(prof4.wishlist[0].item), String(I.i1));
        assert.strictEqual(String(prof4.bookings[0]), String(B.b1));
        assert.strictEqual(w4.customer_name, 'Chitra Sen', "the website's customer keeps the website's name (the app's 'Chitra D' is not copied over it)");
        const prof1 = await site.collection('app_customer_profiles').findOne({ customerId: W.w1 });
        assert.strictEqual(prof1.wishlist[0].status, 'removed');
        const fresh = await site.collection('customers').findOne({ _id: L.l3 });
        assert(fresh && fresh.customer_name === 'Brand New' && fresh.whatsapp_no === '9831112222' && fresh.is_deleted === false && fresh.sl_no === 5 && fresh.notification_type === 'all' && fresh.source === 'merge', `new customer: ${JSON.stringify(fresh)}`);
        assert(await site.collection('app_customer_profiles').findOne({ customerId: L.l3 }));
        assert(!(await site.collection('customers').findOne({ customer_name: 'Bad Number' })), 'a customer without a usable number is skipped, not invented');
        const bk = Object.fromEntries((await site.collection('bookings').find({}).toArray()).map((b) => [String(b._id), b]));
        assert.strictEqual(String(bk[String(B.b1)].customerId), String(W.w4), "a booking made for the app's copy now points at the website's customer");
        assert.strictEqual(String(bk[String(B.b2)].customerId), String(L.l3), 'and one for a new customer keeps its id (that customer now exists on the website)');
        assert.strictEqual(await site.collection('app_sales').countDocuments(), 0, 'no app_sales is created');
        assert.strictEqual((await site.collection('sales').find({}).toArray()).length, 2, "the website's own sales are still just its 2");
        ok('customers: the same person keeps the website record; wishlist/bookings go on the app profile; new people are added the website way (serial, flags); old ids are repointed');

        // plain collections + indexes
        assert.strictEqual(await site.collection('items').countDocuments(), 2);
        assert((await site.collection('items').indexes()).some((i) => i.name === 'barcode_1' && i.unique), 'the unique barcode index came with the items');
        assert.strictEqual(await site.collection('app_settings').countDocuments(), 2);
        assert.strictEqual((await site.collection('settings').countDocuments()), 1);
        ok('the app\'s collections and their indexes are copied; settings went to app_settings, not the website\'s settings');

        // ── again: nothing more happens ──
        const afterApply = await fingerprint(site);
        const again = await merge({ ...args, apply: true });
        assert.strictEqual(await fingerprint(site), afterApply, 'a second run changes nothing');
        assert.strictEqual(again.collections.reduce((a, c) => a + c.added, 0), 0);
        assert.strictEqual(again.users.addedAsNew.length, 0);
        assert.strictEqual(again.users.alreadyMerged, 4);
        assert.strictEqual(again.customers.addedAsNew.length, 0);
        ok('running it again changes nothing at all');
        assert.strictEqual(await fingerprint(app), before.app, 'the app database was never changed');
        ok('the source database is byte-for-byte what it was');

        // ── the new models on the merged database ──
        process.env.MONGODB_URI = `${BASE}/${SITE}`;
        await mongoose.connect(`${BASE}/${SITE}`);
        const User = require('../models/User');
        const store = require('../services/customerStore');
        const login = await User.findByLogin('9830011111', true);
        assert(login && login.name === 'Raju Das' && await login.comparePassword('Site@Pass1'), 'signs in by mobile with the WEBSITE password');
        assert.strictEqual((await User.findByLogin('raju')).id, login.id, 'and by username');
        assert.strictEqual((await User.findByLogin('raju@shop.example')).id, login.id, 'and by e-mail');
        assert.strictEqual((await User.findOne({ legacyAppIds: String(A.a1) })).id, login.id, 'an old app token id finds the same person');
        assert.strictEqual((await User.findById(A.a3)).name, 'Mumbai Manager', 'an app-only person keeps their id');
        assert.strictEqual(await User.taken({ mobile: '9830011111' }), 'mobile number');
        assert.strictEqual(await User.taken({ username: 'sita' }), 'username');
        assert.strictEqual(await User.taken({ mobile: '9999999999', username: 'nobody' }), '');
        assert.strictEqual((await store.findByNumber('9830000009')).customer_name, 'Bimal Das', 'a customer is found by ANY of their numbers');
        assert.strictEqual(await store.findByNumber('9830000004'), null, 'a deleted customer is not found');
        assert.strictEqual(await store.nextSerial(), 6, "the next serial follows the website's rule (highest not deleted + 1)");
        const same = await store.findOrCreate({ name: 'Different Name', mobile: '9830000003', address: 'elsewhere' }, { id: 'u', name: 'U' });
        assert(!same.created && same.customer.customer_name === 'Bimal Das');
        assert.strictEqual((await site.collection('customers').findOne({ _id: W.w2 })).address, 'Howrah', 'an existing customer is not changed by a booking / wishlist / sale');
        const made = await store.findOrCreate({ name: 'Walk In Buyer', mobile: '9876543210', address: 'Park St' }, { id: 'u', name: 'Counter Staff', branchId: 'main', branchName: 'Main branch' });
        assert(made.created && made.customer.sl_no === 6 && made.customer.is_deleted === false && made.customer.whatsapp_no === '9876543210');
        await store.addToWishlist(made.customer, I.i2, { id: 'u', name: 'Counter Staff' });
        assert.strictEqual((await store.wishlistedBy(I.i2)).length, 1);
        ok('on the merged database: sign-in by mobile / username / e-mail with the website password, old ids resolved, customers found by any number, serials follow the website\'s rule');

        console.log('\nall db-merge checks passed');
    } catch (e) {
        console.error('FAILED:', e && e.stack || e);
        process.exitCode = 1;
    } finally {
        await site.dropDatabase().catch(() => {});
        await app.dropDatabase().catch(() => {});
        await client.close().catch(() => {});
        await mongoose.disconnect().catch(() => {});
        process.exit(process.exitCode || 0);
    }
})().catch((e) => { console.error('FAILED:', e && e.stack || e); process.exit(1); });
