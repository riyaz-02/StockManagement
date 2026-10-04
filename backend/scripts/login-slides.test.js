'use strict';
/**
 * The sign-in screen pictures + the long app session, against the REAL server:  node scripts/login-slides.test.js
 * Starts the API on port 5056 (dev database, a fake S3 inside this process). Needs the local database + the dev logins.
 */
const { spawn } = require('child_process');
const path = require('path');
const assert = require('assert');
const sharp = require('sharp');
const { MongoClient } = require('mongodb');
const { fake, objects } = require('./fake-s3');

let n = 0, bad = 0;
const t = async (name, fn) => { try { await fn(); n++; console.log('  ok  ', name); } catch (e) { bad++; console.log('  FAIL', name, '-', e.message); } };
const jwtPayload = (tok) => JSON.parse(Buffer.from(tok.split('.')[1], 'base64url').toString());

(async () => {
    await new Promise((r) => fake.listen(0, '127.0.0.1', r));
    const s3 = `http://127.0.0.1:${fake.address().port}`;
    const PORT = 5056, BASE = `http://127.0.0.1:${PORT}`;
    const srv = spawn(process.execPath, ['server.js'], {
        cwd: path.join(__dirname, '..'),
        env: { ...process.env, PORT: String(PORT), S3_BUCKET: 'slides-test-bucket', S3_ENDPOINT: s3, S3_REGION: 'ap-south-1', AUTH_LIMIT_MAX: '2000', RATE_LIMIT_MAX_REQUESTS: '20000' },
        stdio: 'ignore',
    });
    const stop = () => { try { srv.kill(); } catch (_) { /* gone */ } };
    process.on('exit', stop);
    for (let i = 0; i < 90; i++) { try { const r = await fetch(BASE + '/api/app-version'); if (r.ok) break; } catch (_) { /* not up yet */ } await new Promise((r) => setTimeout(r, 1000)); }

    const api = async (method, url, { token, body, form } = {}) => {
        const headers = {};
        if (token) headers.Authorization = `Bearer ${token}`;
        let payload;
        if (form) payload = form; else if (body !== undefined) { headers['Content-Type'] = 'application/json'; payload = JSON.stringify(body); }
        const r = await fetch(BASE + url, { method, headers, body: payload });
        return { status: r.status, json: await r.json().catch(() => ({})) };
    };
    const login = async (mobile, password, extra = {}) => (await api('POST', '/api/auth/login', { body: { mobile, password, ...extra } })).json?.data?.token;
    const admin = await login('7029621489', 'Admin@123');
    const staff = await login('9000000011', 'Staff@123');
    assert(admin && staff, 'logins failed');

    const cx = await MongoClient.connect('mongodb://127.0.0.1:27018');
    const coll = cx.db('lgp_dev').collection('app_login_slides');
    const before = await coll.find({}).toArray();          // restored at the end
    await coll.deleteMany({});

    const pic = (w, h, bg) => sharp({ create: { width: w, height: h, channels: 3, background: bg } }).jpeg().toBuffer();
    const form = (buf, extra = {}) => { const f = new FormData(); f.append('image', new Blob([buf], { type: 'image/jpeg' }), 'slide.jpg'); for (const [k, v] of Object.entries(extra)) f.append(k, v); return f; };
    let a, b;

    await t('the public list works without a sign-in and starts empty', async () => {
        const r = await api('GET', '/api/app-assets/login-slides');
        assert.strictEqual(r.status, 200);
        assert.deepStrictEqual(r.json.data.slides, []);
    });
    await t('adding a picture needs a sign-in (401) and the permission (403)', async () => {
        assert.strictEqual((await api('POST', '/api/app-assets/login-slides', { form: form(await pic(1080, 1350, '#c33')) })).status, 401);
        assert.strictEqual((await api('POST', '/api/app-assets/login-slides', { token: staff, form: form(await pic(1080, 1350, '#c33')) })).status, 403);
        assert.strictEqual((await api('GET', '/api/app-assets/login-slides/admin', { token: staff })).status, 403);
    });
    await t('an admin adds two pictures: stored in S3 as WebP with a small copy, listed in order', async () => {
        const r1 = await api('POST', '/api/app-assets/login-slides', { token: admin, form: form(await pic(2160, 2700, '#c33'), { captionEn: 'Bill in seconds', captionBn: 'সেকেন্ডে বিল' }) });
        assert.strictEqual(r1.status, 201, JSON.stringify(r1.json));
        a = r1.json.data;
        assert.match(a.imageUrl, /slides-test-bucket\/media\/login\/.*\.webp$/);
        assert(a.thumbUrl && /_t\.webp$/.test(a.thumbUrl));
        assert(Math.max(a.width, a.height) <= 1600, 'the picture was not shrunk');
        const r2 = await api('POST', '/api/app-assets/login-slides', { token: admin, form: form(await pic(1080, 1350, '#36c')) });
        b = r2.json.data;
        const pub = (await api('GET', '/api/app-assets/login-slides')).json.data;
        assert.deepStrictEqual(pub.slides.map((s) => s.id), [a.id, b.id]);
        assert.strictEqual(pub.slides[0].captionBn, 'সেকেন্ডে বিল');
        assert(pub.version && pub.version.includes(a.id));
    });
    await t('a file that is not a picture is refused', async () => {
        const f = new FormData(); f.append('image', new Blob([Buffer.from('MZ-not-a-picture-just-text-here-padding-padding')], { type: 'image/jpeg' }), 'evil.jpg');
        assert.strictEqual((await api('POST', '/api/app-assets/login-slides', { token: admin, form: f })).status, 400);
    });
    await t('captions and on/off can be changed; an off picture is not public but stays in the admin list', async () => {
        const u = await api('PATCH', `/api/app-assets/login-slides/${b.id}`, { token: admin, body: { captionEn: 'Scan fast', active: false } });
        assert.strictEqual(u.json.data.captionEn, 'Scan fast');
        assert.deepStrictEqual((await api('GET', '/api/app-assets/login-slides')).json.data.slides.map((s) => s.id), [a.id]);
        assert.strictEqual((await api('GET', '/api/app-assets/login-slides/admin', { token: admin })).json.data.slides.length, 2);
        await api('PATCH', `/api/app-assets/login-slides/${b.id}`, { token: admin, body: { active: true } });
    });
    await t('reordering puts them in the new order', async () => {
        const r = await api('POST', '/api/app-assets/login-slides/reorder', { token: admin, body: { ids: [b.id, a.id] } });
        assert.deepStrictEqual(r.json.data.slides.map((s) => s.id), [b.id, a.id]);
        assert.deepStrictEqual((await api('GET', '/api/app-assets/login-slides')).json.data.slides.map((s) => s.id), [b.id, a.id]);
    });
    await t('removing a picture removes its file (and small copy) from S3', async () => {
        const key = a.imageUrl.split('slides-test-bucket/')[1];
        assert(objects.has(`slides-test-bucket/${key}`));
        const d = await api('DELETE', `/api/app-assets/login-slides/${a.id}`, { token: admin });
        assert.strictEqual(d.status, 200);
        assert(!objects.has(`slides-test-bucket/${key}`) && !objects.has(`slides-test-bucket/${key.replace('.webp', '_t.webp')}`), 'file still in S3');
        assert.deepStrictEqual((await api('GET', '/api/app-assets/login-slides')).json.data.slides.map((s) => s.id), [b.id]);
        assert.strictEqual((await api('DELETE', `/api/app-assets/login-slides/${a.id}`, { token: admin })).status, 404);
        assert.strictEqual((await api('DELETE', '/api/app-assets/login-slides/not-an-id', { token: admin })).status, 404);
    });
    await t('no more than 8 pictures', async () => {
        for (let i = 0; i < 8; i++) await api('POST', '/api/app-assets/login-slides', { token: admin, form: form(await pic(400, 500, '#999')) });
        const r = await api('POST', '/api/app-assets/login-slides', { token: admin, form: form(await pic(400, 500, '#999')) });
        assert.strictEqual(r.status, 400);
        assert.match(r.json.message, /At most 8/);
        const left = [...objects.keys()].filter((k) => k.includes('/media/login/')).length;
        assert(left <= 16, 'the refused picture was left in S3');
    });

    await t('remember:true lives about 90 days (a plain sign-in keeps the JWT_EXPIRE setting)', async () => {
        const plain = jwtPayload(await login('7029621489', 'Admin@123'));
        const long = jwtPayload(await login('7029621489', 'Admin@123', { remember: true }));
        const days = (p) => (p.exp - p.iat) / 86400;
        assert(days(plain) > 0, 'plain token has no expiry');
        assert(days(long) >= 89 && days(long) <= 91, `remember token lives ${days(long)} days`);
    });
    await t('/auth/refresh swaps a valid token for a fresh long one, and refuses a bad one', async () => {
        const r = await api('POST', '/api/auth/refresh', { token: admin });
        assert.strictEqual(r.status, 200);
        const p = jwtPayload(r.json.data.token);
        assert((p.exp - p.iat) / 86400 >= 89);
        assert.strictEqual((await api('GET', '/api/auth/me', { token: r.json.data.token })).status, 200);
        assert.strictEqual((await api('POST', '/api/auth/refresh', { token: 'garbage' })).status, 401);
        assert.strictEqual((await api('POST', '/api/auth/refresh')).status, 401);
    });

    // leave the dev database as it was
    await coll.deleteMany({});
    if (before.length) await coll.insertMany(before);
    await cx.close();
    stop(); fake.close();
    console.log(`\n${n} passed, ${bad} failed`);
    process.exit(bad ? 1 : 0);
})().catch((e) => { console.error('ERROR', e); process.exit(1); });
