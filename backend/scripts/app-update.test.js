'use strict';
/**
 * The app-update pipeline and the bell, against a RUNNING local API:  node scripts/app-update.test.js [http://localhost:5000]
 * Uses the APK that `flutter build apk --release` made (flutter_app/build/app/outputs/flutter-apk/app-release.apk); skips the
 * APK part when there is none. DEV database only. Puts the version settings back to what they were when it is done.
 */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const assert = require('assert');
const { MongoClient } = require('mongodb');
const { readApk } = require('../services/apkInfo');

const BASE = (process.argv[2] || 'http://localhost:5000').replace(/\/$/, '');
const APK = path.join(__dirname, '..', '..', 'flutter_app', 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
const DB = 'mongodb://127.0.0.1:27018';
let n = 0, bad = 0;
const t = async (name, fn) => { try { await fn(); n++; console.log('  ok  ', name); } catch (e) { bad++; console.log('  FAIL', name, '-', e.message); } };

async function api(method, url, { token, body, form } = {}) {
    const headers = {};
    if (token) headers.Authorization = `Bearer ${token}`;
    let payload;
    if (form) payload = form;
    else if (body !== undefined) { headers['Content-Type'] = 'application/json'; payload = JSON.stringify(body); }
    const r = await fetch(BASE + url, { method, headers, body: payload });
    let json = null; try { json = await r.clone().json(); } catch (_) { /* not json */ }
    return { status: r.status, json, res: r };
}
const login = async (mobile, password) => (await api('POST', '/api/auth/login', { body: { mobile, password } })).json?.data?.token;

(async () => {
    const admin = await login('7029621489', 'Admin@123');
    const staff = await login('9000000011', 'Staff@123');
    assert(admin && staff, 'logins failed (is the dev data seeded?)');
    const cx = await MongoClient.connect(DB);
    const col = cx.db('lgp_dev').collection('appversions');
    const before = await col.findOne({ isActive: true });

    console.log('The bell');
    await t('any signed-in person gets a feed: items, unread, reminders', async () => {
        const r = await api('GET', '/api/notifications/feed', { token: staff });
        assert.strictEqual(r.status, 200);
        assert(Array.isArray(r.json.data.items) && typeof r.json.data.unread === 'number' && typeof r.json.data.reminders === 'number');
    });
    await t('without a token the feed is refused', async () => assert.strictEqual((await api('GET', '/api/notifications/feed')).status, 401));
    await t('a notice sent to everyone shows in the staff feed and counts as unread', async () => {
        const send = await api('POST', '/api/notifications/send', { token: admin, body: { title: 'BELL TEST notice', body: 'hello', targetType: 'all' } });
        assert.strictEqual(send.status, 200, JSON.stringify(send.json));
        const f = (await api('GET', '/api/notifications/feed', { token: staff })).json.data;
        const mine = f.items.find((x) => x.title === 'BELL TEST notice');
        assert(mine && mine.kind === 'notice' && mine.read === false, 'notice missing / already read');
        assert(f.unread >= 1);
    });
    await t('opening the bell marks notices read (reminders stay: they are open jobs)', async () => {
        assert.strictEqual((await api('POST', '/api/notifications/feed/seen', { token: staff })).status, 200);
        const f = (await api('GET', '/api/notifications/feed', { token: staff })).json.data;
        assert(f.items.filter((x) => x.kind === 'notice').every((x) => x.read === true));
        assert.strictEqual(f.unread, f.reminders);
    });
    await t('a notice sent only to admins is not in a staff feed but is in the admin feed', async () => {
        await api('POST', '/api/notifications/send', { token: admin, body: { title: 'BELL TEST admins only', body: 'x', targetType: 'role', targetRole: 'admin' } });
        const s = (await api('GET', '/api/notifications/feed', { token: staff })).json.data.items;
        const a = (await api('GET', '/api/notifications/feed', { token: admin })).json.data.items;
        assert(!s.some((x) => x.title === 'BELL TEST admins only'));
        assert(a.some((x) => x.title === 'BELL TEST admins only'));
    });
    await t('reminders are worked out live (today\'s rate for someone who may set it)', async () => {
        const a = (await api('GET', '/api/notifications/feed', { token: admin })).json.data;
        assert(a.items.every((x) => ['notice', 'reminder'].includes(x.kind)));
        assert(a.reminders === a.items.filter((x) => x.kind === 'reminder').length);
    });

    console.log('\nThe app update');
    await t('the public version answer never shows staged uploads, history or file names', async () => {
        const r = await api('GET', '/api/app-version');
        const v = r.json.data.appVersion;
        assert(!('staged' in v) && !('releases' in v) && !('apk' in v) && !('updatedBy' in v));
    });
    await t('staff cannot upload, publish or read the admin view (403)', async () => {
        assert.strictEqual((await api('POST', '/api/app-version/upload', { token: staff })).status, 403);
        assert.strictEqual((await api('POST', '/api/app-version/publish', { token: staff, body: {} })).status, 403);
        assert.strictEqual((await api('GET', '/api/app-version/admin', { token: staff })).status, 403);
    });
    await t('the download answers 404 clearly when nothing is published', async () => {
        if (before && before.apk && before.apk.file) return;
        assert.strictEqual((await api('GET', '/api/app-version/download')).status, 404);
    });
    await t('publishing with nothing uploaded is refused', async () => {
        await api('DELETE', '/api/app-version/staged', { token: admin });
        const r = await api('POST', '/api/app-version/publish', { token: admin, body: {} });
        assert.strictEqual(r.status, 400); assert(/Upload an APK/.test(r.json.message));
    });
    await t('a file that is not an APK is refused with a plain message', async () => {
        const form = new FormData(); form.append('apk', new Blob(['this is not an app']), 'x.apk');
        const r = await api('POST', '/api/app-version/upload', { token: admin, form });
        assert.strictEqual(r.status, 400); assert(/not an APK/.test(r.json.message), r.json.message);
    });
    await t('no file at all is refused', async () => {
        const r = await api('POST', '/api/app-version/upload', { token: admin, form: new FormData() });
        assert.strictEqual(r.status, 400);
    });

    if (!fs.existsSync(APK)) { console.log('  (no built APK found: the upload / publish / download steps are skipped)'); }
    else {
        const buf = fs.readFileSync(APK);
        const info = await readApk(buf);
        const sha = crypto.createHash('sha256').update(buf).digest('hex');
        await t('the APK is read right: package, version name and code come from the file', async () => {
            assert.strictEqual(info.package, 'com.laltuguineapalace.stock'); assert(info.versionCode > 0 && info.versionName);
        });
        const live = Math.max(before?.latestVersionCode || 0, before?.apk?.versionCode || 0);
        await t('a build that is not newer than what phones have is refused, saying what to do', async () => {
            await col.updateOne({ isActive: true }, { $set: { latestVersionCode: info.versionCode } });
            const form = new FormData(); form.append('apk', new Blob([buf]), 'app.apk');
            const r = await api('POST', '/api/app-version/upload', { token: admin, form });
            assert.strictEqual(r.status, 400); assert(/higher build number/.test(r.json.message), r.json.message);
        });
        // pretend phones are one build behind, so this APK is the update
        await col.updateOne({ isActive: true }, { $set: { latestVersionCode: info.versionCode - 1 } });
        await t('upload: checked, kept as staged, nothing published yet', async () => {
            const form = new FormData(); form.append('apk', new Blob([buf]), 'app.apk');
            const r = await api('POST', '/api/app-version/upload', { token: admin, form });
            assert.strictEqual(r.status, 201, JSON.stringify(r.json));
            assert.strictEqual(r.json.data.staged.versionCode, info.versionCode); assert.strictEqual(r.json.data.staged.sha256, sha);
            const pub = (await api('GET', '/api/app-version')).json.data.appVersion;
            assert.strictEqual(pub.latestVersionCode, info.versionCode - 1, 'staging must not change what phones see');
            const adm = (await api('GET', '/api/app-version/admin', { token: admin })).json.data.appVersion;
            assert(adm.staged && adm.staged.versionName === info.versionName && !adm.staged.file);
        });
        await t('publish: the version, the link and the checksum go live; the bell gets a line', async () => {
            const r = await api('POST', '/api/app-version/publish', { token: admin, body: { forceUpdate: false, updateMessage: 'TEST release notes' } });
            assert.strictEqual(r.status, 200, JSON.stringify(r.json));
            const v = (await api('GET', '/api/app-version')).json.data.appVersion;
            assert.strictEqual(v.latestVersionCode, info.versionCode); assert.strictEqual(v.latestVersion, info.versionName);
            assert.strictEqual(v.downloadUrl, '/api/app-version/download'); assert.strictEqual(v.apkSha256, sha); assert.strictEqual(v.apkSize, buf.length);
            assert.strictEqual(v.updateMessage, 'TEST release notes'); assert.strictEqual(v.forceUpdate, false);
            const f = (await api('GET', '/api/notifications/feed', { token: staff })).json.data.items;
            assert(f.some((x) => x.source === 'app-update' && x.link === 'update'), 'no update line in the bell');
        });
        await t('the same build cannot be published twice', async () => {
            const form = new FormData(); form.append('apk', new Blob([buf]), 'app.apk');
            assert.strictEqual((await api('POST', '/api/app-version/upload', { token: admin, form })).status, 400);
            assert.strictEqual((await api('POST', '/api/app-version/publish', { token: admin, body: {} })).status, 400);
        });
        await t('download: the whole file, the right type, the checksum header; no login needed', async () => {
            const r = await fetch(BASE + '/api/app-version/download');
            assert.strictEqual(r.status, 200);
            assert.match(r.headers.get('content-type'), /android\.package-archive/);
            assert.strictEqual(r.headers.get('x-content-sha256'), sha);
            const got = Buffer.from(await r.arrayBuffer());
            assert.strictEqual(crypto.createHash('sha256').update(got).digest('hex'), sha);
        });
        await t('download can resume: a Range request returns just that part', async () => {
            const r = await fetch(BASE + '/api/app-version/download', { headers: { Range: 'bytes=0-99' } });
            assert.strictEqual(r.status, 206);
            assert.strictEqual(Buffer.from(await r.arrayBuffer()).length, 100);
        });
        await t('history: the release is listed with who and when', async () => {
            const adm = (await api('GET', '/api/app-version/admin', { token: admin })).json.data.appVersion;
            assert(adm.releases[0].versionCode === info.versionCode && adm.releases[0].publishedByName);
        });
        // put it back as it was
        const apkDir = path.join(__dirname, '..', 'storage', 'apk');
        if (before) await col.replaceOne({ _id: before._id }, before); else await col.deleteMany({});
        try { for (const f of fs.readdirSync(apkDir)) if (/^LaltuGuineaPalace-/.test(f) && !(before?.apk?.file === f)) fs.unlinkSync(path.join(apkDir, f)); } catch (_) { /* nothing to clean */ }
    }
    await cx.db('lgp_dev').collection('notifications').deleteMany({ title: { $in: ['BELL TEST notice', 'BELL TEST admins only'] } });
    await cx.db('lgp_dev').collection('notifications').deleteMany({ source: 'app-update', body: 'TEST release notes' });
    await cx.close();
    console.log(`\n${n} passed, ${bad} failed`);
    process.exit(bad ? 1 : 0);
})().catch((e) => { console.error('ERROR', e); process.exit(1); });
