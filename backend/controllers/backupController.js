/**
 * backupController.js - "Data backup" (Admin Control): paste a MongoDB connection string, see what is in it, download all of it.
 * Admin/owner only (the router gate). Read-only on the database being copied. The connection string is never stored or logged.
 */
'use strict';
const svc = require('../services/dbBackup');
const audit = require('../services/audit');
const logger = require('../config/logger');

const fail = (e, res, next) => (e instanceof svc.BackupError ? res.status(e.status).json({ success: false, message: e.message }) : next(e));

// POST /api/admin/backup/inspect { uri } -> { host, defaultDb, databases: [{ name, collections: [{ name, type, count, sizeBytes }], totalDocs, totalBytes }] }
exports.inspect = async (req, res, next) => {
    try {
        res.json({ success: true, data: await svc.inspect(req.body && req.body.uri) });
    } catch (e) { fail(e, res, next); }
};

// POST /api/admin/backup/download { uri, databases?: [name], includeReadable?: bool } -> the .zip itself (or a JSON error BEFORE any file bytes)
exports.download = async (req, res, next) => {
    const b = req.body || {};
    const databases = Array.isArray(b.databases) ? b.databases.map(String).slice(0, 50) : [];
    try {
        const sum = await svc.backup(b.uri, { databases, includeReadable: b.includeReadable !== false }, ({ filename }) => {
            res.status(200);
            res.setHeader('Content-Type', 'application/zip');
            res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
            res.setHeader('Cache-Control', 'no-store');
            res.setHeader('X-Accel-Buffering', 'no'); // a proxy in front must pass the file on as it is made
            return res;
        });
        logger.info(`[backup] ${req.user && req.user.name} copied ${sum.documents} documents (${sum.databases} database(s), ${sum.bytes} bytes) from ${sum.host}`);
        audit.record(req, 'backup', 'raw', sum.host, 'downloaded', [
            { field: 'databases', to: String(sum.databases) }, { field: 'collections', to: String(sum.collections) },
            { field: 'documents', to: String(sum.documents) }, { field: 'zip size (bytes)', to: String(sum.bytes) },
        ]);
    } catch (e) {
        if (res.headersSent) {
            logger.error(`[backup] stopped part-way: ${e.message}`);
            res.destroy(e); // the half-made zip is unusable on purpose: the person sees the download fail instead of trusting a partial file
            return;
        }
        fail(e, res, next);
    }
};
