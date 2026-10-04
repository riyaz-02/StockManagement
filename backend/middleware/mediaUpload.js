/**
 * mediaUpload.js - the one upload middleware for photos, PDFs and videos.
 *
 *   mediaUpload({ allow: ['image'], maxBytes, folder: (req) => 'items' }).single('image')   /   .array('images', 5)
 *
 * The file is received into a temporary file (never held in memory: a video can be large), checked by what it REALLY is,
 * then saved to S3 (see services/mediaStore.js) - or to Cloudinary while no S3 bucket is configured. Afterwards each
 * req.file has the same fields the old Cloudinary uploader gave, so the controllers did not need to change:
 *     file.path = the public link   file.filename = the id used to delete it   file.format / width / height / size
 *     file.thumbUrl = the small copy of a photo (S3 only)
 * The temporary file is always removed.
 */
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const multer = require('multer');
const store = require('../services/mediaStore');

const KIND_MIMES = {
    image: ['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'image/heic', 'image/heif'],
    pdf: ['application/pdf'],
    video: ['video/mp4', 'video/quicktime', 'video/webm'],
};
const MB = 1024 * 1024;

function tempFileOf(req, file, cb) { cb(null, `lgp-upload-${Date.now()}-${crypto.randomBytes(6).toString('hex')}`); }

async function toCloudinary(file, folder, allow) {
    // the fallback while S3 is not set up yet (same behaviour as before this change)
    const cloudinary = require('../config/cloudinary');
    const isPdf = file.mimetype === 'application/pdf';
    const isVideo = file.mimetype.startsWith('video/');
    const r = await cloudinary.uploader.upload(file.path, {
        folder: `jewelry-stock/${folder}`,
        resource_type: isPdf ? 'raw' : isVideo ? 'video' : 'image',
        ...(isPdf || isVideo ? {} : { transformation: [{ width: 1600, height: 1600, crop: 'limit' }, { quality: 'auto:good' }] }),
    });
    return { url: r.secure_url, publicId: r.public_id, format: r.format || (isPdf ? 'pdf' : 'image'), width: r.width, height: r.height, size: r.bytes };
}

function mediaUpload({ allow = ['image'], maxBytes = 10 * MB, folder = () => 'items', maxSide, thumb = true } = {}) {
    // The declared type is only a first filter (apps name it loosely, e.g. image/JPG or octet-stream): the real check is
    // by the file's own first bytes (mediaStore.sniff) once it has arrived.
    const declaredOk = (mime) => {
        const t = String(mime || '').toLowerCase();
        return t === 'application/octet-stream' || allow.some((k) => (k === 'image' && t.startsWith('image/')) || (k === 'video' && t.startsWith('video/')) || (KIND_MIMES[k] || []).includes(t));
    };
    const m = multer({
        storage: multer.diskStorage({ destination: os.tmpdir(), filename: tempFileOf }),
        limits: { fileSize: maxBytes, files: 10 },
        fileFilter: (req, file, cb) => (declaredOk(file.mimetype) ? cb(null, true) : cb(Object.assign(new Error(`Only ${allow.join(' / ')} files are allowed here`), { status: 400, code: 'BAD_TYPE' }), false)),
    });

    const processFiles = async (req) => {
        const files = req.file ? [req.file] : Array.isArray(req.files) ? req.files : [];
        const dir = String(folder(req) || 'items');
        for (const f of files) {
            if (store.enabled()) {
                const r = await store.saveFile(f, { folder: dir, allow, maxSide, thumb });
                f.mimetype = r.format === 'webp' ? 'image/webp' : f.mimetype;
                Object.assign(f, { path: r.url, filename: r.publicId, format: r.format, width: r.width, height: r.height, size: r.size, thumbUrl: r.thumbUrl || '', storage: 's3' });
            } else {
                const r = await toCloudinary(f, dir, allow);
                Object.assign(f, { path: r.url, filename: r.publicId, format: r.format, width: r.width, height: r.height, size: r.size || f.size, thumbUrl: '', storage: 'cloudinary' });
            }
        }
    };

    const wrap = (inner) => (req, res, next) => {
        const temps = () => [req.file, ...(req.files || [])].filter(Boolean).map((f) => f.__tmp).filter(Boolean);
        inner(req, res, async (err) => {
            // remember each temporary file so it is removed whatever happens
            for (const f of [req.file, ...(Array.isArray(req.files) ? req.files : [])].filter(Boolean)) f.__tmp = f.path;
            const cleanup = () => temps().forEach((p) => fs.unlink(p, () => {}));
            if (err) {
                cleanup();
                const msg = err.code === 'LIMIT_FILE_SIZE' ? `The file is too large (the limit is ${Math.round(maxBytes / MB)} MB)` : err.code === 'LIMIT_UNEXPECTED_FILE' ? 'Too many files, or the wrong field name' : err.message;
                return res.status(err.status || 400).json({ success: false, message: msg });
            }
            try {
                await processFiles(req);
                res.on('finish', cleanup);
                res.on('close', cleanup);
                next();
            } catch (e) {
                cleanup();
                console.error('[upload] failed:', e.message);
                res.status(e.status || 500).json({ success: false, message: e.status ? e.message : 'The file could not be saved. Try again.' });
            }
        });
    };

    return {
        single: (field) => wrap(m.single(field)),
        array: (field, n) => wrap(m.array(field, n)),
    };
}

/** Which folder an upload belongs to: ?folder= (items | containers | users | ...), else the page it came from. */
function folderFromRequest(req) {
    const q = String(req.query.folder || '').toLowerCase();
    if (q) return q;
    if (/container/i.test(req.headers.referer || '') || /container/i.test(req.path || '')) return 'containers';
    return 'items';
}

module.exports = { mediaUpload, folderFromRequest, KIND_MIMES, MB };
