// The unified User model (the website's `users` collection + the app's fields), against a throw-away LOCAL database.
// Run: node scripts/user-model.test.js
'use strict';
require('dotenv').config();
const assert = require('assert');
const { execFileSync } = require('child_process');
const mongoose = require('mongoose');
const m = /^(mongodb:\/\/(?:127\.0\.0\.1|localhost)(?::\d+)?)/.exec(process.env.MONGODB_URI || '');
assert(m, 'refusing to run: MONGODB_URI is not a local database');
const dbName = `um_test_${Date.now()}`;
const ok = (n) => console.log('ok -', n);

const phpHash = (pw) => execFileSync('php', ['-r', 'echo password_hash($argv[1], PASSWORD_DEFAULT);', '--', pw]).toString();
const phpVerify = (pw, hash) => execFileSync('php', ['-r', 'echo password_verify($argv[1], $argv[2]) ? "yes" : "no";', '--', pw, hash]).toString() === 'yes';

(async () => {
    await mongoose.connect(`${m[1]}/${dbName}`);
    const User = require('../models/User');
    const raw = mongoose.connection.db.collection('users');
    try {
        // ── people exactly as the website's PHP writes them ──
        const siteHash = phpHash('Site@Pass1');
        const now = new Date();
        const raju = (await raw.insertOne({ username: 'raju', email: 'raju@shop.example', password: siteHash, full_name: 'Raju Das', role: 'Admin', contact: '9830011111', address: 'Kolkata', profile_image: '', created_at: now, is_active: true, status: 'active', remember_token: 'keep-me' })).insertedId;
        const sita = (await raw.insertOne({ username: 'sita', email: 'sita@shop.example', password: siteHash, full_name: 'Sita Roy', role: 'user', contact: '9830022222', is_active: false, status: 'inactive', created_at: now })).insertedId;

        const u = await User.findById(raju).select('+password');
        assert.strictEqual(u.name, 'Raju Das', 'name is the website full_name');
        assert.strictEqual(u.isActive, true);
        assert.strictEqual(u.role, 'admin', "the website's 'Admin' reads as admin");
        assert.strictEqual(await u.comparePassword('Site@Pass1'), true, "a PHP password_hash() password is accepted by the app");
        assert.strictEqual(await u.comparePassword('nope'), false);
        assert.strictEqual(u.branchId, 'main');
        ok("a person written by the website is read correctly: name, active, 'Admin' as admin, PHP password accepted");

        // ── queries written with the app's own names still work ──
        assert.strictEqual((await User.find({ isActive: true })).length, 1, 'find by isActive');
        assert.strictEqual((await User.find({ isActive: false })).length, 1);
        assert.strictEqual((await User.findOne({ name: 'Sita Roy' }))._id.toString(), sita.toString(), 'find by name');
        assert.strictEqual((await User.countDocuments({ role: 'admin' })), 0, 'role is matched as stored (a legacy "Admin" is not the string "admin" in a filter)');
        assert.strictEqual((await User.findOne({ $or: [{ mobile: 'x' }, { username: 'raju' }, { email: 'zzz' }] }))._id.toString(), raju.toString(), 'sign in by username');
        const sel = await User.findById(raju).select('name role isActive').lean();
        assert(sel.full_name === 'Raju Das' || sel.name === 'Raju Das', 'select by the app names returns the name');
        ok("queries written with the app's names (isActive, name) are translated to the website's fields");

        // ── a person made by the app is a normal website user too ──
        const made = await User.create({ name: 'Mumbai Staff', mobile: '9000000099', password: 'App@Pass22', role: 'staff', username: '9000000099', branchId: 'MUM', branchName: 'Mumbai Branch' });
        const stored = await raw.findOne({ _id: made._id });
        assert.strictEqual(stored.full_name, 'Mumbai Staff');
        assert.strictEqual(stored.is_active, true);
        assert.strictEqual(stored.status, 'active');
        assert.strictEqual(stored.username, '9000000099');
        assert.strictEqual(stored.email, '', 'email is always present (the website reads it at sign-in)');
        assert(stored.created_at instanceof Date, 'created_at is a date, like the website writes it');
        assert(/^\$2[aby]\$/.test(stored.password) && stored.password !== 'App@Pass22', 'password stored hashed');
        assert.strictEqual(phpVerify('App@Pass22', stored.password), true, "the website's password_verify accepts a password set in the app");
        assert.strictEqual(stored.branchId, 'MUM');
        assert(!('name' in stored) && !('isActive' in stored), 'no second copy of name/isActive is stored');
        ok("a person made in the app is stored in the website's own fields, and the website's PHP accepts their password");

        // ── saving does not disturb what the website keeps ──
        const again = await User.findById(raju);
        again.branchId = 'BAG';
        again.language = 'bn';
        await again.save();
        const after = await raw.findOne({ _id: raju });
        assert.strictEqual(after.remember_token, 'keep-me', "the website's own fields survive a save from the app");
        assert.strictEqual(after.password, siteHash, 'the password is not re-hashed by an unrelated save');
        assert.strictEqual(after.role, 'Admin', "the website's role text is left exactly as it was");
        assert.strictEqual(after.branchId, 'BAG');
        ok("an app-side save changes only what it changed (password, role text and the website's extras untouched)");

        // ── one switch for both sides ──
        const t = await User.findById(raju);
        t.isActive = false;
        await t.save();
        assert.strictEqual((await raw.findOne({ _id: raju })).is_active, false, "deactivating in the app writes the website's is_active");
        await raw.updateOne({ _id: raju }, { $set: { is_active: true } });
        assert.strictEqual((await User.findById(raju)).isActive, true, 'and re-activating on the website shows in the app');
        ok('active / inactive is one value, shared by the website and the app');

        // ── what leaves the API ──
        const j = JSON.parse(JSON.stringify(await User.findById(raju)));
        assert(!('password' in j) && j.name === 'Raju Das' && j.isActive === true && j.role === 'admin' && j.mobile === '9830011111' && j.username === 'raju');
        ok('the JSON the API sends has the names the app and portal expect and never the password');

        // ── a website-only person (phone only in `contact`) can sign in on the app with it, when it is unambiguous ──
        assert.strictEqual(String((await User.findByLogin('9830011111'))._id), String(raju));
        assert.strictEqual(String((await User.findByLogin('+91 98300-11111'))._id), String(raju));
        await raw.insertOne({ username: 'twin1', password: siteHash, full_name: 'Twin One', role: 'staff', contact: '9830099999', is_active: true, created_at: now });
        await raw.insertOne({ username: 'twin2', password: siteHash, full_name: 'Twin Two', role: 'staff', contact: '9830099999', is_active: true, created_at: now });
        assert.strictEqual(await User.findByLogin('9830099999'), null, 'a number shared by two people logs nobody in');
        assert.strictEqual(await User.findByLogin('nobody'), null);
        ok('the phone number the website stores in contact signs a person in, but never when two people share it');

        // ── a legacy app id is found ──
        await raw.updateOne({ _id: sita }, { $set: { legacyAppIds: ['64b000000000000000000001'] } });
        assert.strictEqual((await User.findOne({ legacyAppIds: '64b000000000000000000001' }))._id.toString(), sita.toString());
        ok('an old app id kept on a merged person can be looked up');

        console.log('\nall user-model checks passed');
    } finally {
        await mongoose.connection.db.dropDatabase().catch(() => {});
        await mongoose.disconnect();
    }
})().catch((e) => { console.error('FAILED:', e && e.stack || e); process.exit(1); });
