'use strict';
/**
 * Uploads to S3, tested end to end WITHOUT AWS: a tiny S3-compatible server runs in this process (single PUT, multipart,
 * GET, DELETE) and the real AWS SDK talks to it.   node scripts/media-store.test.js
 * Covers: photo shrunk + small copy + location stripped, PNG keeps transparency, PDF / video / HEIC stored as they are, a big
 * video through multipart, a fake file refused whatever it is called, wrong kind / too big refused, delete (main + small copy),
 * the temporary files removed, links recognised as ours.
 */
const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');
const assert = require('assert');
const crypto = require('crypto');
const express = require('express');
const sharp = require('sharp');

const { fake, objects } = require('./fake-s3');

let n = 0, bad = 0;
const t = async (name, fn) => { try { await fn(); n++; console.log('  ok  ', name); } catch (e) { bad++; console.log('  FAIL', name, '-', e.message); } };

const post = async (base, route, field, buf, filename, mime) => {
    const fd = new FormData();
    fd.append(field, new Blob([buf], { type: mime }), filename);
    const r = await fetch(base + route, { method: 'POST', body: fd });
    return { status: r.status, json: await r.json().catch(() => ({})) };
};
const tmpLeft = () => fs.readdirSync(os.tmpdir()).filter((f) => f.startsWith('lgp-upload-')).length;

(async () => {
    await new Promise((r) => fake.listen(0, '127.0.0.1', r));
    process.env.S3_BUCKET = 'test-bucket';
    process.env.S3_REGION = 'ap-south-1';
    process.env.S3_ENDPOINT = `http://127.0.0.1:${fake.address().port}`;
    delete process.env.S3_PUBLIC_BASE_URL;
    const store = require('../services/mediaStore');
    const { mediaUpload, MB } = require('../middleware/mediaUpload');

    const app = express();
    app.use(express.json());
    const photos = mediaUpload({ allow: ['image'], maxBytes: 12 * MB, folder: () => 'items' });
    const bills = mediaUpload({ allow: ['image', 'pdf'], maxBytes: 15 * MB, folder: () => 'purchase-bills', maxSide: 2000, thumb: false });
    const anything = mediaUpload({ allow: ['image', 'pdf', 'video'], maxBytes: 60 * MB, folder: () => 'videos' });
    const view = (f) => ({ url: f.path, publicId: f.filename, thumbUrl: f.thumbUrl, format: f.format, width: f.width, height: f.height, size: f.size });
    app.post('/photo', photos.single('image'), (req, res) => res.json(view(req.file)));
    app.post('/photos', photos.array('images', 3), (req, res) => res.json({ images: req.files.map(view) }));
    app.post('/bill', bills.single('attachment'), (req, res) => res.json(view(req.file)));
    app.post('/any', anything.single('file'), (req, res) => res.json(view(req.file)));
    app.post('/delete', async (req, res) => res.json({ ok: await store.removeByUrl(req.body.url) }));
    const srv = await new Promise((r) => { const s = app.listen(0, '127.0.0.1', () => r(s)); });
    const base = `http://127.0.0.1:${srv.address().port}`;
    const get = (url) => objects.get(url.replace(process.env.S3_ENDPOINT + '/', ''));

    // a 3000x2000 photo with a GPS location in it
    const big = await sharp({ create: { width: 3000, height: 2000, channels: 3, background: '#c0392b' } }).withExif({ IFD3: { GPSLatitudeRef: 'N', GPSLatitude: '22/1 33/1 0/1' } }).jpeg({ quality: 90 }).toBuffer();
    let first;

    await t('a photo is stored on S3 as WebP: shrunk to 1600 px, with a small copy, under media/items/yyyy/mm/', async () => {
        const r = await post(base, '/photo', 'image', big, 'ring.jpg', 'image/jpeg');
        assert.strictEqual(r.status, 200, JSON.stringify(r.json));
        first = r.json;
        assert.match(first.url, /\/test-bucket\/media\/items\/\d{4}\/\d{2}\/[0-9a-f]{24}\.webp$/);
        assert.strictEqual(first.publicId.startsWith('media/items/'), true);
        assert.strictEqual(Math.max(first.width, first.height), 1600);
        assert.match(first.thumbUrl, /_t\.webp$/);
        const main = get(first.url), th = get(first.thumbUrl);
        assert(main && th, 'objects missing');
        assert.strictEqual(main.type, 'image/webp');
        assert.match(main.cache, /max-age=31536000/);
        const tm = await sharp(th.body).metadata();
        assert(Math.max(tm.width, tm.height) <= 400 && th.body.length < main.body.length);
    });
    await t('the stored photo carries no GPS location', async () => {
        const m = await sharp(get(first.url).body).metadata();
        assert(!m.exif || !/GPS/i.test(m.exif.toString('latin1')), 'EXIF still there');
    });
    await t('an upright photo stays upright (EXIF turn applied)', async () => {
        const rot = await sharp({ create: { width: 800, height: 400, channels: 3, background: '#00f' } }).jpeg().withMetadata({ orientation: 6 }).toBuffer();
        const r = await post(base, '/photo', 'image', rot, 'r.jpg', 'image/jpeg');
        assert.strictEqual(r.status, 200);
        assert(r.json.height > r.json.width, `${r.json.width}x${r.json.height}`);
    });
    await t('a PNG with transparency is stored as WebP and stays transparent', async () => {
        const png = await sharp({ create: { width: 300, height: 300, channels: 4, background: { r: 255, g: 0, b: 0, alpha: 0.5 } } }).png().toBuffer();
        const r = await post(base, '/photo', 'image', png, 'logo.png', 'image/png');
        assert.strictEqual(r.status, 200);
        assert.match(r.json.url, /\.webp$/);
        assert.strictEqual((await sharp(get(r.json.url).body).metadata()).hasAlpha, true);
    });
    await t('several photos in one request', async () => {
        const fd = new FormData();
        for (let i = 0; i < 3; i++) fd.append('images', new Blob([big], { type: 'image/jpeg' }), `p${i}.jpg`);
        const r = await fetch(base + '/photos', { method: 'POST', body: fd });
        const j = await r.json();
        assert.strictEqual(j.images.length, 3);
        assert.strictEqual(new Set(j.images.map((x) => x.url)).size, 3, 'links must differ');
    });
    await t('a purchase-bill PDF is stored as it is (no thumbnail)', async () => {
        const pdf = Buffer.concat([Buffer.from('%PDF-1.4\n'), crypto.randomBytes(5000), Buffer.from('\n%%EOF')]);
        const r = await post(base, '/bill', 'attachment', pdf, 'bill.pdf', 'application/pdf');
        assert.strictEqual(r.status, 200, JSON.stringify(r.json));
        assert.match(r.json.url, /media\/purchase-bills\/.*\.pdf$/);
        assert.strictEqual(get(r.json.url).body.equals(pdf), true);
        assert.strictEqual(get(r.json.url).type, 'application/pdf');
        assert(!r.json.thumbUrl);
    });
    await t('the WebP is smaller than a JPEG of the same photo and still sharp', async () => {
        const photo = await sharp({ create: { width: 1600, height: 1200, channels: 3, noise: { type: 'gaussian', mean: 128, sigma: 20 } } }).jpeg({ quality: 90 }).toBuffer();
        const r = await post(base, '/photo', 'image', photo, 'n.jpg', 'image/jpeg');
        assert.strictEqual(r.status, 200);
        assert(r.json.size < photo.length, `${r.json.size} vs ${photo.length}`);
    });
    await t('a bill photo may be larger (2000 px)', async () => {
        const r = await post(base, '/bill', 'attachment', big, 'bill.jpg', 'image/jpeg');
        assert.strictEqual(Math.max(r.json.width, r.json.height), 2000);
    });
    await t('a short video is stored as it is', async () => {
        const mp4 = Buffer.concat([Buffer.from([0, 0, 0, 24]), Buffer.from('ftypisom'), Buffer.from([0, 0, 2, 0]), Buffer.from('isomiso2'), crypto.randomBytes(200000)]);
        const r = await post(base, '/any', 'file', mp4, 'clip.mp4', 'video/mp4');
        assert.strictEqual(r.status, 200, JSON.stringify(r.json));
        assert.match(r.json.url, /media\/videos\/.*\.mp4$/);
        assert.strictEqual(get(r.json.url).body.equals(mp4), true);
    });
    await t('a 25 MB video goes up in parts (multipart) and arrives whole', async () => {
        const head = Buffer.concat([Buffer.from([0, 0, 0, 24]), Buffer.from('ftypisom'), Buffer.from([0, 0, 2, 0]), Buffer.from('isomiso2')]);
        const mp4 = Buffer.concat([head, crypto.randomBytes(25 * 1024 * 1024)]);
        const r = await post(base, '/any', 'file', mp4, 'big.mp4', 'video/mp4');
        assert.strictEqual(r.status, 200, JSON.stringify(r.json));
        assert.strictEqual(get(r.json.url).body.length, mp4.length);
        assert.strictEqual(crypto.createHash('md5').update(get(r.json.url).body).digest('hex'), crypto.createHash('md5').update(mp4).digest('hex'));
    });
    await t('a HEIC photo (cannot be re-encoded here) is stored as it is', async () => {
        const heic = Buffer.concat([Buffer.from([0, 0, 0, 24]), Buffer.from('ftypheic'), Buffer.from([0, 0, 0, 0]), Buffer.from('mif1heic'), crypto.randomBytes(3000)]);
        const r = await post(base, '/photo', 'image', heic, 'x.heic', 'image/heic');
        assert.strictEqual(r.status, 200, JSON.stringify(r.json));
        assert.match(r.json.url, /\.heic$/);
    });
    await t('a text file called photo.jpg is refused: the real content decides', async () => {
        const r = await post(base, '/photo', 'image', Buffer.from('<?php system($_GET[0]); ?> not a picture at all'), 'photo.jpg', 'image/jpeg');
        assert.strictEqual(r.status, 400, JSON.stringify(r.json));
        assert.match(r.json.message, /not allowed/);
    });
    await t('a program renamed to .pdf is refused', async () => {
        const r = await post(base, '/bill', 'attachment', Buffer.concat([Buffer.from('MZ'), crypto.randomBytes(500)]), 'bill.pdf', 'application/pdf');
        assert.strictEqual(r.status, 400);
    });
    await t('a PDF sent to the photo route is refused (wrong kind)', async () => {
        const r = await post(base, '/photo', 'image', Buffer.from('%PDF-1.4 ' + 'x'.repeat(100)), 'a.pdf', 'application/pdf');
        assert.strictEqual(r.status, 400);
    });
    await t('a video sent where only photos are allowed is refused', async () => {
        const r = await post(base, '/photo', 'image', Buffer.concat([Buffer.from([0, 0, 0, 24]), Buffer.from('ftypisom'), crypto.randomBytes(300)]), 'v.mp4', 'video/mp4');
        assert.strictEqual(r.status, 400);
    });
    await t('a file over the limit is refused with the limit in the message', async () => {
        const r = await post(base, '/photo', 'image', Buffer.concat([big, Buffer.alloc(13 * 1024 * 1024)]), 'huge.jpg', 'image/jpeg');
        assert.strictEqual(r.status, 400);
        assert.match(r.json.message, /too large.*12 MB/);
    });
    await t('a damaged picture is refused, not stored', async () => {
        const before = objects.size;
        const r = await post(base, '/photo', 'image', Buffer.concat([Buffer.from('ffd8ffe000104a464946', 'hex'), crypto.randomBytes(200)]), 'bad.jpg', 'image/jpeg');
        assert([400, 500].includes(r.status));
        assert.strictEqual(objects.size, before);
    });
    await t('deleting a link removes the photo and its small copy', async () => {
        const th = first.thumbUrl;
        const r = await (await fetch(base + '/delete', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ url: first.url }) })).json();
        assert.strictEqual(r.ok, true);
        assert(!get(first.url) && !get(th), 'still there');
    });
    await t('a link that is not ours (or not a link) deletes nothing', async () => {
        const before = objects.size;
        for (const url of ['https://example.com/media/x.jpg', '', 'media/../etc', 'https://other-bucket.s3.ap-south-1.amazonaws.com/media/a.jpg']) {
            assert.strictEqual(await store.removeByUrl(url), false);
        }
        assert.strictEqual(objects.size, before);
    });
    await t('our links are recognised (S3 address, CloudFront address); Cloudinary is told apart', async () => {
        assert.strictEqual(store.keyOfUrl('https://test-bucket.s3.ap-south-1.amazonaws.com/media/items/2026/10/a.jpg'), 'media/items/2026/10/a.jpg');
        process.env.S3_PUBLIC_BASE_URL = 'https://files.example.com';
        assert.strictEqual(store.keyOfUrl('https://files.example.com/media/items/a.jpg'), 'media/items/a.jpg');
        assert.strictEqual(store.publicUrl('media/items/a.jpg'), 'https://files.example.com/media/items/a.jpg');
        assert.strictEqual(store.thumbOf('https://files.example.com/media/items/a.webp'), 'https://files.example.com/media/items/a_t.webp');
        delete process.env.S3_PUBLIC_BASE_URL;
        assert.strictEqual(store.isCloudinaryUrl('https://res.cloudinary.com/x/image/upload/v1/a.jpg'), true);
        assert.strictEqual(store.keyOfUrl('https://res.cloudinary.com/x/image/upload/v1/a.jpg'), null);
    });
    await t('no temporary file is left behind', async () => {
        await new Promise((r) => setTimeout(r, 400));
        assert.strictEqual(tmpLeft(), 0);
    });
    await t('the file type is read from the bytes', async () => {
        assert.strictEqual(store.sniff(big).kind, 'image');
        assert.strictEqual(store.sniff(Buffer.from('%PDF-1.7 ......')).kind, 'pdf');
        assert.strictEqual(store.sniff(Buffer.from('hello world, plain text')), null);
    });

    srv.close(); fake.close();
    console.log(`\n${n} passed, ${bad} failed`);
    process.exit(bad ? 1 : 0);
})().catch((e) => { console.error('ERROR', e); process.exit(1); });
