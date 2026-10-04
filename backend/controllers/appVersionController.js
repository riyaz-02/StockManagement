const AppVersion = require('../models/AppVersion');

const DEFAULTS = {
    latestVersion: '1.0.0',
    latestVersionCode: 1,
    forceUpdate: false,
    downloadUrl: 'https://lgp.skriyaz.com/app',
    updateMessage: 'A new version of the app is available.',
};

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const APK_DIR = process.env.APK_DIR || path.join(__dirname, '..', 'storage', 'apk');
const PACKAGE = process.env.APP_PACKAGE || 'com.laltuguineapalace.stock';
const MAX_APK = 300 * 1024 * 1024;
const APK_PATH = '/api/app-version/download';   // relative: the phone adds the server address it already talks to

/** What any phone may see: the version rules and the facts needed to check a download. No file names, no staged upload. */
function publicView(c) {
    const o = { ...c };
    const apk = o.apk && o.apk.file ? o.apk : null;
    delete o.staged; delete o.releases; delete o.apk; delete o.updatedBy;
    if (apk) { o.downloadUrl = o.downloadUrl || APK_PATH; o.apkSha256 = apk.sha256; o.apkSize = apk.sizeBytes; o.apkFromServer = true; }
    return o;
}

// @desc    Get current app version config (public — checked before login)
// @route   GET /api/app-version
// @access  Public
exports.getAppVersion = async (req, res) => {
    try {
        const config = (await AppVersion.findOne({ isActive: true }).lean()) || DEFAULTS;

        res.status(200).json({
            success: true,
            data: { appVersion: publicView(config) },
        });
    } catch (error) {
        console.error('Get app version error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while fetching app version',
        });
    }
};

// @desc    Update app version config
// @route   PUT /api/app-version
// @access  Private/Admin
exports.updateAppVersion = async (req, res) => {
    try {
        const { latestVersion, latestVersionCode, forceUpdate, downloadUrl, updateMessage } = req.body;

        if (!latestVersion || latestVersionCode === undefined) {
            return res.status(400).json({
                success: false,
                message: 'Please provide latestVersion and latestVersionCode',
            });
        }

        const update = {
            latestVersion,
            latestVersionCode: Number(latestVersionCode),
            forceUpdate: !!forceUpdate,
            updatedBy: req.user.id,
        };
        if (downloadUrl !== undefined) update.downloadUrl = downloadUrl;
        if (updateMessage !== undefined) update.updateMessage = updateMessage;

        const beforeCfg = (await AppVersion.findOne({ isActive: true }).lean()) || {};
        const config = await AppVersion.findOneAndUpdate(
            { isActive: true },
            { $set: update },
            { new: true, upsert: true, setDefaultsOnInsert: true }
        );

        {
            const now = { version: config.latestVersion, code: config.latestVersionCode, forceUpdate: !!config.forceUpdate, downloadUrl: config.downloadUrl || '', message: config.updateMessage || '' };
            const was = { version: beforeCfg.latestVersion, code: beforeCfg.latestVersionCode, forceUpdate: !!beforeCfg.forceUpdate, downloadUrl: beforeCfg.downloadUrl || '', message: beforeCfg.updateMessage || '' };
            const changes = Object.keys(now).filter((k) => String(now[k]) !== String(was[k])).map((k) => ({ field: k, from: was[k], to: now[k] }));
            require('../services/audit').record(req, 'app_update', 'app', 'App version ' + config.latestVersion, 'published', changes);
        }
        require('../services/events').emit('app.update', { latestVersion: config.latestVersion, latestVersionCode: config.latestVersionCode, forceUpdate: !!config.forceUpdate, updateMessage: config.updateMessage || '' }, { actor: { id: req.user._id, name: req.user.name } });
        res.status(200).json({
            success: true,
            message: 'App version updated',
            data: { appVersion: config },
        });
    } catch (error) {
        console.error('Update app version error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while updating app version',
        });
    }
};

// @desc    Turn the sign-in gate on/off (blocks new logins on the app and the website; admin/owner can always still sign in)
// @route   PUT /api/app-version/maintenance
// @access  Private/Admin
exports.updateMaintenanceMode = async (req, res) => {
    try {
        const enabled = req.body.enabled === true;
        const message = String(req.body.message || '').trim().slice(0, 200) || DEFAULTS.updateMessage;
        const before = (await AppVersion.findOne({ isActive: true }).lean()) || {};
        const config = await AppVersion.findOneAndUpdate(
            { isActive: true },
            { $set: { maintenanceMode: { enabled, message }, updatedBy: req.user.id } },
            { new: true, upsert: true, setDefaultsOnInsert: true }
        );
        const was = !!(before.maintenanceMode && before.maintenanceMode.enabled);
        if (was !== enabled) {
            require('../services/audit').record(req, 'app_update', 'app', 'Sign-in gate', enabled ? 'turned on' : 'turned off', [{ field: 'enabled', from: was, to: enabled }, { field: 'message', to: message }]);
        }
        res.status(200).json({ success: true, data: { appVersion: config } });
    } catch (error) {
        console.error('Update maintenance mode error:', error);
        res.status(500).json({ success: false, message: 'Server error while updating the sign-in gate' });
    }
};

// ── uploading and publishing an update (Admin > App updates) ─────────────────────────────────────────────────
const multer = require('multer');

const incoming = multer({
    storage: multer.diskStorage({
        destination: (req, file, cb) => { fs.mkdirSync(APK_DIR, { recursive: true }); cb(null, APK_DIR); },
        filename: (req, file, cb) => cb(null, `incoming-${Date.now()}-${crypto.randomBytes(4).toString('hex')}.tmp`),
    }),
    limits: { fileSize: MAX_APK, files: 1 },
}).single('apk');

const sha256File = (file) => new Promise((resolve, reject) => {
    const h = crypto.createHash('sha256');
    fs.createReadStream(file).on('data', (d) => h.update(d)).on('end', () => resolve(h.digest('hex'))).on('error', reject);
});
const safeUnlink = (f) => { try { if (f) fs.unlinkSync(f); } catch (_) { /* already gone */ } };
const fileIn = (name) => path.join(APK_DIR, path.basename(String(name || '')));
const fail = (res, code, message) => res.status(code).json({ success: false, message });
const EMPTY_STAGED = { file: '', versionName: '', versionCode: 0, sizeBytes: 0, sha256: '', uploadedAt: null, uploadedByName: '' };

// @desc    Everything the admin page shows: the live version, the staged upload and the history
// @route   GET /api/app-version/admin
exports.getAdminView = async (req, res, next) => {
    try {
        const c = (await AppVersion.findOne({ isActive: true }).lean()) || {};
        const staged = c.staged && c.staged.file ? { ...c.staged, file: undefined } : null;
        res.json({ success: true, data: { appVersion: { ...publicView(c), apk: c.apk && c.apk.file ? { ...c.apk, file: undefined } : null, staged, releases: (c.releases || []).slice(-10).reverse(), package: PACKAGE } } });
    } catch (e) { next(e); }
};

// @desc    Upload an APK: it is read, checked and kept as "staged"; nothing reaches the phones until it is published
// @route   POST /api/app-version/upload   (multipart, field "apk")
exports.uploadApk = (req, res) => {
    incoming(req, res, async (err) => {
        const tmp = req.file && req.file.path;
        try {
            if (err) return fail(res, 400, err.code === 'LIMIT_FILE_SIZE' ? `The file is too large (the limit is ${Math.round(MAX_APK / 1048576)} MB)` : `The upload failed: ${err.message}`);
            if (!req.file) return fail(res, 400, 'Choose the APK file to upload');
            let info;
            try { info = await require('../services/apkInfo').readApk(fs.readFileSync(tmp)); } catch (e) { safeUnlink(tmp); return fail(res, 400, e.message); }
            if (info.package !== PACKAGE) { safeUnlink(tmp); return fail(res, 400, `This APK is for "${info.package}", not for this shop's app (${PACKAGE}). Choose the right file.`); }
            const cur = (await AppVersion.findOne({ isActive: true }).lean()) || {};
            const live = Math.max(Number(cur.latestVersionCode) || 0, Number((cur.apk && cur.apk.versionCode) || 0));
            if (info.versionCode <= live) { safeUnlink(tmp); return fail(res, 400, `Its version code is ${info.versionCode}, but phones already have ${live}. Build it again with a higher build number (pubspec.yaml: version: x.y.z+N, with N above ${live}).`); }
            const sha = await sha256File(tmp);
            const final = `LaltuGuineaPalace-${info.versionName}+${info.versionCode}.apk`;
            fs.renameSync(tmp, fileIn(final));
            // a replaced staged file is removed (the published one is never touched here)
            const old = cur.staged && cur.staged.file;
            if (old && old !== final && old !== (cur.apk && cur.apk.file)) safeUnlink(fileIn(old));
            const staged = { file: final, versionName: info.versionName, versionCode: info.versionCode, sizeBytes: req.file.size, sha256: sha, uploadedAt: new Date(), uploadedByName: req.user.name || '' };
            await AppVersion.findOneAndUpdate({ isActive: true }, { $set: { staged } }, { upsert: true, setDefaultsOnInsert: true });
            require('../services/audit').record(req, 'app_update', 'app', `APK ${info.versionName} (${info.versionCode})`, 'uploaded', [{ field: 'size', to: `${(req.file.size / 1048576).toFixed(1)} MB` }, { field: 'sha256', to: sha.slice(0, 16) }]);
            res.status(201).json({ success: true, message: 'The APK is checked and ready to publish', data: { staged: { ...staged, file: undefined, signed: info.signed } } });
        } catch (e) {
            safeUnlink(tmp);
            console.error('Upload APK error:', e);
            fail(res, 500, 'Server error while saving the APK');
        }
    });
};

// @desc    Publish the staged APK: phones are told (push + live event) and can download it
// @route   POST /api/app-version/publish   { forceUpdate, updateMessage }
exports.publishApk = async (req, res, next) => {
    try {
        const cur = await AppVersion.findOne({ isActive: true }).lean();
        const st = cur && cur.staged;
        if (!st || !st.file || !fs.existsSync(fileIn(st.file))) return fail(res, 400, 'Upload an APK first');
        const live = Math.max(Number(cur.latestVersionCode) || 0, Number((cur.apk && cur.apk.versionCode) || 0));
        if (st.versionCode <= live) return fail(res, 409, `Version code ${st.versionCode} is not above the published ${live}. Upload a newer build.`);
        const force = req.body.forceUpdate === true || req.body.forceUpdate === 'true' || req.body.forceUpdate === 'on' || req.body.forceUpdate === '1';
        const message = String(req.body.updateMessage || '').trim().slice(0, 300);
        const now = new Date();
        const apk = { file: st.file, versionName: st.versionName, versionCode: st.versionCode, sizeBytes: st.sizeBytes, sha256: st.sha256, publishedAt: now };
        const release = { versionName: st.versionName, versionCode: st.versionCode, sizeBytes: st.sizeBytes, sha256: st.sha256, publishedAt: now, publishedByName: req.user.name || '', forceUpdate: force, message };
        const config = await AppVersion.findOneAndUpdate(
            { isActive: true },
            { $set: { latestVersion: st.versionName, latestVersionCode: st.versionCode, forceUpdate: force, updateMessage: message || 'A new version of the app is available.', downloadUrl: APK_PATH, apk, updatedBy: req.user.id, staged: EMPTY_STAGED }, $push: { releases: { $each: [release], $slice: -30 } } },
            { new: true }
        ).lean();
        // keep the last three published files (for a rollback), remove older ones
        try {
            const keep = new Set([...(config.releases || []).slice(-3).map((r) => `LaltuGuineaPalace-${r.versionName}+${r.versionCode}.apk`), st.file]);
            for (const f of fs.readdirSync(APK_DIR)) if (/^LaltuGuineaPalace-.+\.apk$/.test(f) && !keep.has(f)) safeUnlink(path.join(APK_DIR, f));
        } catch (_) { /* cleaning is best effort */ }

        // tell every phone: a live event for the ones open now, a push for the rest, and a line in everyone's bell
        const title = force ? `Update required · v${st.versionName}` : `Update available · v${st.versionName}`;
        const body = message || 'A new version of the shop app is ready. Tap to update.';
        let result = { successCount: 0, failureCount: 0, invalidTokens: [] };
        try {
            const { resolveTargetTokens, pruneInvalidTokens } = require('./notificationController');
            result = await require('../config/firebaseAdmin').sendPushToTokens(await resolveTargetTokens({ targetType: 'all' }), { title, body, data: { source: 'app-update', versionCode: st.versionCode, force } });
            await pruneInvalidTokens(result.invalidTokens);
        } catch (e) { console.error('Update push failed:', e.message); }
        await require('../models/Notification').create({ title, body, data: { versionName: st.versionName, versionCode: st.versionCode, force }, targetType: 'all', source: 'app-update', sentBy: req.user.id, successCount: result.successCount, failureCount: result.failureCount });
        require('../services/audit').record(req, 'app_update', 'app', `App version ${st.versionName}`, 'published', [{ field: 'version', to: `${st.versionName} (${st.versionCode})` }, { field: 'forceUpdate', to: String(force) }, { field: 'pushed', to: `${result.successCount} device(s)` }]);
        require('../services/events').emit('app.update', { latestVersion: config.latestVersion, latestVersionCode: config.latestVersionCode, forceUpdate: force, updateMessage: message }, { actor: { id: req.user._id, name: req.user.name } });
        require('../services/events').emit('notification.new', { title, body }, { actor: { id: req.user._id, name: req.user.name } });
        res.json({ success: true, message: `Version ${st.versionName} is published`, data: { appVersion: publicView(config), pushed: result.successCount } });
    } catch (e) { next(e); }
};

// @desc    Throw away the staged (not yet published) upload
// @route   DELETE /api/app-version/staged
exports.discardStaged = async (req, res, next) => {
    try {
        const cur = await AppVersion.findOne({ isActive: true }).lean();
        const f = cur && cur.staged && cur.staged.file;
        if (f && f !== (cur.apk && cur.apk.file)) safeUnlink(fileIn(f));
        await AppVersion.updateOne({ isActive: true }, { $set: { staged: EMPTY_STAGED } });
        res.json({ success: true });
    } catch (e) { next(e); }
};

// @desc    Download the published APK (public: the update screen and the download page use it; it supports resuming)
// @route   GET /api/app-version/download
exports.downloadApk = async (req, res, next) => {
    try {
        const c = await AppVersion.findOne({ isActive: true }).lean();
        const f = c && c.apk && c.apk.file;
        if (!f || !fs.existsSync(fileIn(f))) return fail(res, 404, 'No app update has been uploaded yet');
        res.set({ 'Content-Type': 'application/vnd.android.package-archive', 'Content-Disposition': `attachment; filename="${f}"`, 'X-Content-SHA256': c.apk.sha256, 'Cache-Control': 'no-cache' });
        res.sendFile(fileIn(f));       // Range requests (a download that was cut off continues) are handled by sendFile
    } catch (e) { next(e); }
};
