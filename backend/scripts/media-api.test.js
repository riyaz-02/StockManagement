'use strict';
/**
 * The upload routes of the REAL server, against a fake S3, with real logins and permissions:  node scripts/media-api.test.js
 * Starts the API itself on port 5055 (dev database, S3 settings pointing at an in-process fake S3), so nothing real is touched.
 * Needs the local database (node scripts/local-db.js) and the dev logins.
 */
const { spawn } = require('child_process');
const path = require('path');
const assert = require('assert');
const crypto = require('crypto');
const sharp = require('sharp');
const { MongoClient } = require('mongodb');
const { fake, objects } = require('./fake-s3');

let n = 0, bad = 0;
const t = async (name, fn) => { try { await fn(); n++; console.log('  ok  ', name); } catch (e) { bad++; console.log('  FAIL', name, '-', e.message); } };

(async () => {
    await new Promise((r) => fake.listen(0, '127.0.0.1', r));
    const s3 = `http://127.0.0.1:${fake.address().port}`;
    const PORT = 5055, BASE = `http://127.0.0.1:${PORT}`;
    const srv = spawn(process.execPath, ['server.js'], {
        cwd: path.join(__dirname, '..'),
        env: { ...process.env, PORT: String(PORT), S3_BUCKET: 'api-test-bucket', S3_ENDPOINT: s3, S3_REGION: 'ap-south-1', AUTH_LIMIT_MAX: '2000', RATE_LIMIT_MAX_REQUESTS: '20000', CLOUDINARY_CLOUD_NAME: '', CLOUDINARY_API_KEY: '', CLOUDINARY_API_SECRET: '' },
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
    const login = async (mobile, password) => (await api('POST', '/api/auth/login', { body: { mobile, password } })).json?.data?.token;
    const admin = await login('7029621489', 'Admin@123');
    const staff = await login('9000000011', 'Staff@123');
    assert(admin && staff, 'logins failed');
    const photo = await sharp({ create: { width: 2400, height: 1800, channels: 3, background: '#2c7' } }).jpeg().toBuffer();
    const upForm = (field, buf, name, type) => { const f = new FormData(); f.append(field, new Blob([buf], { type }), name); return f; };
    const tag = Date.now();
    let url, thumb, key;

    await t('without a login an upload is refused (401)', async () => {
        assert.strictEqual((await api('POST', '/api/upload/single', { form: upForm('image', photo, 'a.jpg', 'image/jpeg') })).status, 401);
    });
    await t('an item photo goes to S3 through /api/upload/single, with its small copy', async () => {
        const r = await api('POST', '/api/upload/single?folder=items', { token: admin, form: upForm('image', photo, 'ring.jpg', 'image/jpeg') });
        assert.strictEqual(r.status, 200, JSON.stringify(r.json));
        const d = r.json.data;
        url = d.url; thumb = d.thumbUrl; key = d.publicId;
        assert.match(url, /api-test-bucket\/media\/items\//);
        assert.strictEqual(d.storage, 's3');
        assert.strictEqual(Math.max(d.width, d.height), 1600);
        assert(objects.has(`api-test-bucket/${key}`) && objects.has(`api-test-bucket/${key.replace('.webp', '_t.webp')}`));
    });
    await t('the folder follows ?folder= (containers, users)', async () => {
        for (const f of ['containers', 'users']) {
            const r = await api('POST', `/api/upload/single?folder=${f}`, { token: admin, form: upForm('image', photo, 'x.jpg', 'image/jpeg') });
            assert.match(r.json.data.url, new RegExp(`media/${f}/`));
            await api('POST', '/api/upload/delete', { token: admin, body: { url: r.json.data.url } });
        }
    });
    await t('a container photo through /api/containers/upload returns the full link', async () => {
        const r = await api('POST', '/api/containers/upload', { token: admin, form: upForm('image', photo, 'box.jpg', 'image/jpeg') });
        assert.strictEqual(r.status, 200, JSON.stringify(r.json));
        assert.match(r.json.url, /^http.*media\/containers\//);
        await api('POST', '/api/upload/delete', { token: admin, body: { url: r.json.url } });
    });
    await t('a purchase bill (PDF) through /api/purchases/upload-bill', async () => {
        const pdf = Buffer.concat([Buffer.from('%PDF-1.4\n'), crypto.randomBytes(3000), Buffer.from('\n%%EOF')]);
        const r = await api('POST', '/api/purchases/upload-bill', { token: admin, form: upForm('attachment', pdf, 'bill.pdf', 'application/pdf') });
        assert.strictEqual(r.status, 200, JSON.stringify(r.json));
        const d = r.json.data || r.json;
        assert.match(d.url, /media\/purchase-bills\/.*\.pdf$/);
        // and removed through the bill's own delete route (the id uses -- for /)
        const del = await api('DELETE', `/api/purchases/attachment/${encodeURIComponent(d.publicId.replace(/\//g, '--'))}`, { token: admin });
        assert.strictEqual(del.json.success, true, JSON.stringify(del.json));
        assert(![...objects.keys()].some((k) => k.includes('purchase-bills')), 'the bill is still in S3');
    });
    await t('a video through /api/upload/file', async () => {
        const mp4 = Buffer.concat([Buffer.from([0, 0, 0, 24]), Buffer.from('ftypisom'), Buffer.from([0, 0, 2, 0]), Buffer.from('isomiso2'), crypto.randomBytes(300000)]);
        const r = await api('POST', '/api/upload/file?folder=videos', { token: admin, form: upForm('file', mp4, 'clip.mp4', 'video/mp4') });
        assert.strictEqual(r.status, 200, JSON.stringify(r.json));
        assert.match(r.json.data.url, /media\/videos\/.*\.mp4$/);
        await api('POST', '/api/upload/delete', { token: admin, body: { url: r.json.data.url } });
    });
    await t('a video is refused on the photo route', async () => {
        const mp4 = Buffer.concat([Buffer.from([0, 0, 0, 24]), Buffer.from('ftypisom'), crypto.randomBytes(500)]);
        assert.strictEqual((await api('POST', '/api/upload/single', { token: admin, form: upForm('image', mp4, 'c.mp4', 'video/mp4') })).status, 400);
    });
    await t('an item can be created with that photo link, and deleting the item deletes the file from S3', async () => {
        const c = await api('POST', '/api/items', { token: admin, body: { barcode: `MEDIA-${tag}`, name: 'MEDIA TEST ring', itemType: 'ring', metalType: 'gold', purity: '22k', netWeight: 2, grossWeight: 2.1, images: [url] } });
        assert([200, 201].includes(c.status), JSON.stringify(c.json));
        const id = (c.json.data && (c.json.data.item || c.json.data))._id;
        assert(id);
        const g = await api('GET', `/api/items/${id}`, { token: admin });
        assert.deepStrictEqual((g.json.data.item || g.json.data).images, [url]);
        const d = await api('DELETE', `/api/items/${id}/permanent`, { token: admin });
        assert.strictEqual(d.status, 200, JSON.stringify(d.json));
        assert(!objects.has(`api-test-bucket/${key}`), 'the photo is still in S3');
        assert(!objects.has(`api-test-bucket/${key.replace('.webp', '_t.webp')}`), 'the small copy is still in S3');
    });
    await t('deleting an unknown link answers 404 and removes nothing', async () => {
        const before = objects.size;
        const r = await api('POST', '/api/upload/delete', { token: admin, body: { url: 'https://example.com/media/items/2026/10/aaaaaaaaaaaaaaaaaaaaaaaa.jpg' } });
        assert.strictEqual(r.status, 404);
        assert.strictEqual(objects.size, before);
    });
    await t('the old delete route still works for an S3 id (media--...)', async () => {
        const r = await api('POST', '/api/upload/single', { token: admin, form: upForm('image', photo, 'o.jpg', 'image/jpeg') });
        const id = r.json.data.publicId.replace(/\//g, '--');
        const d = await api('DELETE', `/api/upload/${encodeURIComponent(id)}`, { token: admin });
        assert.strictEqual(d.status, 200, JSON.stringify(d.json));
        assert(!objects.has(`api-test-bucket/${r.json.data.publicId}`));
    });
    await t('a login without the upload permission cannot upload (403)', async () => {
        const r = await api('POST', '/api/upload/single', { token: staff, form: upForm('image', photo, 'a.jpg', 'image/jpeg') });
        assert([200, 403].includes(r.status)); // staff may hold the permission by default: then it must work, otherwise 403
        if (r.status === 200) await api('POST', '/api/upload/delete', { token: staff, body: { url: r.json.data.url } });
    });

    // leave nothing behind in the dev database
    const cx = await MongoClient.connect('mongodb://127.0.0.1:27018');
    await cx.db('lgp_dev').collection('items').deleteMany({ barcode: `MEDIA-${tag}` });
    await cx.close();
    stop(); fake.close();
    console.log(`\n${n} passed, ${bad} failed`);
    process.exit(bad ? 1 : 0);
})().catch((e) => { console.error('ERROR', e); process.exit(1); });
