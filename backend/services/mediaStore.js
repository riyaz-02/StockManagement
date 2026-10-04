/**
 * mediaStore.js - where uploaded files (photos, PDFs, videos ...) are kept.
 *
 *   NEW files go to Amazon S3 (when S3_BUCKET is set). Cloudinary keeps serving the files it already holds: their links
 *   are stored as full https URLs in the database, so nothing about them changes, and deleting one still goes to Cloudinary.
 *   Until a bucket is configured, uploads fall back to Cloudinary so nothing breaks while S3 is being set up.
 *
 * Settings (backend/.env):
 *   S3_BUCKET            the bucket name (turns S3 on)
 *   S3_REGION            default ap-south-1 (Mumbai)
 *   S3_PUBLIC_BASE_URL   optional: the address files are served from (a CloudFront address). Default: the bucket's own address.
 *   S3_ENDPOINT          optional: an S3-compatible server (local tests only)
 *   credentials          none to set on EC2: the instance's IAM role is used. (Locally: AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY.)
 *
 * Keys look like  media/<folder>/<yyyy>/<mm>/<random>.<ext>  (and  ..._t.webp  for the small copy of a photo). The random part
 * makes a link impossible to guess; the folder says what the file is for.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const PREFIX = 'media/';
const KEY_SHAPE = /^media\/[a-z0-9_-]+\/\d{4}\/\d{2}\/[0-9a-f]{24}(_t)?\.[a-z0-9]{2,5}$/;
const IMAGE_MAX_SIDE = 1600;          // photos are shrunk to this (the app already sends <= 1600)
const BILL_IMAGE_MAX_SIDE = 2000;     // a scanned bill needs to stay readable
const THUMB_SIDE = 400;
const WEBP_QUALITY = 85;

let _client = null;
const bucket = () => String(process.env.S3_BUCKET || '').trim();
const region = () => String(process.env.S3_REGION || 'ap-south-1').trim();
const enabled = () => !!bucket();

function client() {
    if (_client) return _client;
    const { S3Client } = require('@aws-sdk/client-s3');
    const cfg = { region: region() };
    if (process.env.S3_ENDPOINT) { cfg.endpoint = process.env.S3_ENDPOINT; cfg.forcePathStyle = true; cfg.credentials = { accessKeyId: process.env.AWS_ACCESS_KEY_ID || 'test', secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY || 'test' }; }
    _client = new S3Client(cfg);
    return _client;
}
function resetClient() { _client = null; }

/** The address a stored file is served from. */
function publicUrl(key) {
    const base = String(process.env.S3_PUBLIC_BASE_URL || '').trim().replace(/\/$/, '');
    if (base) return `${base}/${key}`;
    if (process.env.S3_ENDPOINT) return `${process.env.S3_ENDPOINT.replace(/\/$/, '')}/${bucket()}/${key}`;
    return `https://${bucket()}.s3.${region()}.amazonaws.com/${key}`;
}

/** Is this link one of ours (an S3 file)? -> its key, else null. */
function keyOfUrl(url) {
    const u = String(url || '').trim();
    if (!u) return null;
    const bases = [];
    if (process.env.S3_PUBLIC_BASE_URL) bases.push(String(process.env.S3_PUBLIC_BASE_URL).replace(/\/$/, '') + '/');
    if (bucket()) {
        bases.push(`https://${bucket()}.s3.${region()}.amazonaws.com/`);
        bases.push(`https://${bucket()}.s3.amazonaws.com/`);
        if (process.env.S3_ENDPOINT) bases.push(`${process.env.S3_ENDPOINT.replace(/\/$/, '')}/${bucket()}/`);
    }
    for (const b of bases) {
        if (u.startsWith(b)) {
            const key = decodeURIComponent(u.slice(b.length).split('?')[0]);
            return key.startsWith(PREFIX) ? key : null;
        }
    }
    return null;
}
const isCloudinaryUrl = (u) => /^https?:\/\/res\.cloudinary\.com\//i.test(String(u || ''));

// ── what a file really is (the browser's / app's word for it is not trusted) ──────────────────────────────────────────
function sniff(buf) {
    if (!buf || buf.length < 12) return null;
    const hex = buf.slice(0, 12).toString('hex');
    if (hex.startsWith('ffd8ff')) return { kind: 'image', ext: 'jpg', mime: 'image/jpeg' };
    if (hex.startsWith('89504e470d0a1a0a')) return { kind: 'image', ext: 'png', mime: 'image/png' };
    if (buf.slice(0, 4).toString() === 'RIFF' && buf.slice(8, 12).toString() === 'WEBP') return { kind: 'image', ext: 'webp', mime: 'image/webp' };
    if (buf.slice(0, 4).toString() === '%PDF') return { kind: 'pdf', ext: 'pdf', mime: 'application/pdf' };
    if (buf.slice(4, 8).toString() === 'ftyp') {
        const brand = buf.slice(8, 12).toString();
        if (/^(heic|heix|hevc|mif1|msf1)/.test(brand)) return { kind: 'image', ext: 'heic', mime: 'image/heic' };
        if (brand === 'qt  ') return { kind: 'video', ext: 'mov', mime: 'video/quicktime' };
        return { kind: 'video', ext: 'mp4', mime: 'video/mp4' };
    }
    if (hex.startsWith('1a45dfa3')) return { kind: 'video', ext: 'webm', mime: 'video/webm' };
    return null;
}

const rand = () => crypto.randomBytes(12).toString('hex');
const safeFolder = (f) => String(f || 'misc').toLowerCase().replace(/[^a-z0-9_-]/g, '').slice(0, 40) || 'misc';

async function putStream(key, body, mime, size) {
    const { Upload } = require('@aws-sdk/lib-storage');
    await new Upload({
        client: client(),
        params: { Bucket: bucket(), Key: key, Body: body, ContentType: mime, CacheControl: 'public, max-age=31536000, immutable' },
        queueSize: 2, partSize: 8 * 1024 * 1024, leavePartsOnError: false,
    }).done();
    return size;
}

/**
 * Save one uploaded file (already on disk) to S3.
 * @returns {Promise<{url, key, publicId, thumbUrl?, format, width?, height?, size, kind}>}
 * Throws an Error with a readable message for a file that is not allowed.
 */
async function saveFile(file, { folder = 'items', allow = ['image'], maxSide = IMAGE_MAX_SIDE, thumb = true } = {}) {
    const head = Buffer.alloc(16);
    const fd = fs.openSync(file.path, 'r');
    try { fs.readSync(fd, head, 0, 16, 0); } finally { fs.closeSync(fd); }
    const t = sniff(head);
    if (!t || !allow.includes(t.kind)) {
        throw Object.assign(new Error(`This kind of file is not allowed here (${allow.join(', ')} only)`), { status: 400 });
    }
    const d = new Date();
    const dir = `${PREFIX}${safeFolder(folder)}/${d.getUTCFullYear()}/${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
    const id = rand();
    const out = { kind: t.kind };

    if (t.kind === 'image' && t.ext !== 'heic') {
        // photos: turned upright, shrunk and saved as WebP (about 17-35 % smaller than JPEG at the same look; keeps transparency).
        // Quality 85 measured on this shop's own photos: ~41 dB against the original = not visible to the eye. This also drops the
        // phone's GPS location from the picture.
        const sharp = require('sharp');
        const img = sharp(file.path, { failOn: 'error' }).rotate();
        const main = await img.clone().resize({ width: maxSide, height: maxSide, fit: 'inside', withoutEnlargement: true }).webp({ quality: WEBP_QUALITY, effort: 4, smartSubsample: true }).toBuffer({ resolveWithObject: true });
        const key = `${dir}/${id}.webp`;
        await putStream(key, main.data, 'image/webp', main.data.length);
        Object.assign(out, { key, url: publicUrl(key), publicId: key, format: 'webp', width: main.info.width, height: main.info.height, size: main.data.length });
        if (thumb) {
            const tb = await img.clone().resize({ width: THUMB_SIDE, height: THUMB_SIDE, fit: 'inside', withoutEnlargement: true }).webp({ quality: 75, effort: 4 }).toBuffer();
            const tkey = `${dir}/${id}_t.webp`;
            await putStream(tkey, tb, 'image/webp', tb.length);
            out.thumbKey = tkey;
            out.thumbUrl = publicUrl(tkey);
        }
        return out;
    }

    // PDFs, videos (and HEIC photos, which cannot be re-encoded here) are stored as they are, streamed
    const key = `${dir}/${id}.${t.ext}`;
    const stat = fs.statSync(file.path);
    await putStream(key, fs.createReadStream(file.path), t.mime, stat.size);
    Object.assign(out, { key, url: publicUrl(key), publicId: key, format: t.ext, size: stat.size });
    return out;
}

/** Delete a stored file given its link (S3 or Cloudinary) or an S3 key. Never throws: -> true when it is gone. */
async function removeByUrl(urlOrKey) {
    const v = String(urlOrKey || '').trim();
    if (!v) return false;
    try {
        const key = v.startsWith(PREFIX) ? v : keyOfUrl(v);
        if (key) {
            // only a key of the exact shape this system creates may be deleted (never a guessed or hand-made path)
            if (!KEY_SHAPE.test(key)) return false;
            const { DeleteObjectsCommand } = require('@aws-sdk/client-s3');
            const keys = [{ Key: key }];
            // the small copy goes with its photo (older files had a .jpg one)
            if (/\.(webp|jpg|png)$/i.test(key) && !/_t\.(webp|jpg)$/i.test(key)) {
                keys.push({ Key: key.replace(/\.(webp|jpg|png)$/i, '_t.webp') });
                if (!/\.webp$/i.test(key)) keys.push({ Key: key.replace(/\.(jpg|png)$/i, '_t.jpg') });
            }
            await client().send(new DeleteObjectsCommand({ Bucket: bucket(), Delete: { Objects: keys } }));
            return true;
        }
        if (isCloudinaryUrl(v)) return await require('../utils/cloudinaryHelper').destroyCloudinaryUrl(v);
    } catch (e) {
        console.error('[mediaStore] delete failed:', e.message);
    }
    return false;
}

/** The small copy's link for a stored photo (S3 only); anything else has none. */
function thumbOf(url) {
    const key = keyOfUrl(url);
    if (!key || !/\.(webp|jpg|png)$/i.test(key) || /_t\.(webp|jpg)$/i.test(key)) return '';
    return publicUrl(key.replace(/\.(webp|jpg|png)$/i, /\.webp$/i.test(key) ? '_t.webp' : '_t.jpg'));
}

module.exports = { enabled, saveFile, removeByUrl, keyOfUrl, publicUrl, thumbOf, sniff, isCloudinaryUrl, resetClient, PREFIX, BILL_IMAGE_MAX_SIDE };
