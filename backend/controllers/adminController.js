/**
 * adminController.js — environment status for the admin dashboard (/admin).
 *
 * Read-only. Reports what this server is running (commit, uptime), whether
 * each database connection is healthy, and which config keys are set.
 * It NEVER returns environment-variable values or connection strings — only
 * whether each key is set — so it is safe to compare dev and prod.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execFileSync } = require('child_process');
const mongoose = require('mongoose');
const { getConnection } = require('../config/db');
const { ALL_KEYS } = require('../config/permissions');

const startedAt = new Date();
const ROOT = path.join(__dirname, '..');

function git(...args) {
    try {
        return execFileSync('git', args, { cwd: ROOT, timeout: 3000, stdio: ['ignore', 'pipe', 'ignore'] })
            .toString().trim();
    } catch { return null; }
}

// Cached: git state cannot change without a restart/deploy of this process.
let gitInfo;
function getGitInfo() {
    if (!gitInfo) {
        gitInfo = {
            commit: git('rev-parse', '--short', 'HEAD') || process.env.GIT_COMMIT || null,
            branch: git('rev-parse', '--abbrev-ref', 'HEAD') || null,
            message: git('log', '-1', '--pretty=%s') || null,
            committedAt: git('log', '-1', '--pretty=%cI') || null,
        };
    }
    return gitInfo;
}

// Keys the server expects, taken from .env.example so the list never drifts.
function expectedEnvKeys() {
    try {
        const txt = fs.readFileSync(path.join(ROOT, '.env.example'), 'utf8');
        return [...txt.matchAll(/^([A-Z][A-Z0-9_]*)=/gm)].map((m) => m[1]);
    } catch {
        return ['MONGODB_URI', 'JWT_SECRET'];
    }
}
const REQUIRED = new Set(['MONGODB_URI', 'JWT_SECRET']);   // MONGODB_URI is the one database address (the old SHOPMANAGE_DB_URI / LGP_ADMIN_DB_URI are gone)

const STATES = ['disconnected', 'connected', 'connecting', 'disconnecting'];

async function dbHealth(label, getConn, envKey) {
    if (!process.env[envKey]) return { label, configured: false, state: 'not configured' };
    let conn;
    try { conn = getConn(); } catch { return { label, configured: true, state: 'not initialised' }; }
    const out = { label, configured: true, state: STATES[conn.readyState] || 'unknown', db: conn.name };
    if (conn.readyState === 1) {
        const t0 = Date.now();
        try {
            await conn.db.admin().ping();
            out.pingMs = Date.now() - t0;
        } catch (e) {
            out.state = 'ping failed';
            out.error = e.message;
        }
    }
    return out;
}

// GET /api/admin/status
exports.status = async (req, res, next) => {
    try {
        const pkg = require('../package.json');
        const databases = [await dbHealth('Database (app + website)', getConnection, 'MONGODB_URI')];

        const env = expectedEnvKeys().map((key) => ({
            key,
            set: !!process.env[key],
            required: REQUIRED.has(key),
        }));

        res.json({
            success: true,
            data: {
                generatedAt: new Date().toISOString(),
                app: {
                    name: pkg.name,
                    version: pkg.version,
                    node: process.version,
                    environment: process.env.NODE_ENV || 'development',
                    startedAt: startedAt.toISOString(),
                    uptimeSec: Math.round(process.uptime()),
                    ...getGitInfo(),
                },
                databases,
                env,
                // Same hash on two servers ⇔ same permission definitions deployed.
                permissionsHash: crypto.createHash('sha1').update(ALL_KEYS.join('|')).digest('hex').slice(0, 10),
                permissionCount: ALL_KEYS.length,
            },
        });
    } catch (e) { next(e); }
};

// GET /api/admin/audit?entity=&q=&from=&to=&page=&limit= : the audit log, newest first (customer / supplier / staff edits and admin actions)
exports.audit = async (req, res, next) => {
    try {
        const AuditLog = require('../models/AuditLog');
        const page = Math.max(1, parseInt(req.query.page, 10) || 1);
        const limit = Math.min(100, Math.max(1, parseInt(req.query.limit, 10) || 50));
        const f = {};
        const entity = String(req.query.entity || '').trim();
        if (entity) f.entity = entity;
        const q = String(req.query.q || '').trim().slice(0, 60);
        if (q) {
            const special = '.*+?^${}()|[]' + String.fromCharCode(92);
            const rx = new RegExp(q.split('').map((c) => (special.includes(c) ? String.fromCharCode(92) + c : c)).join(''), 'i');
            f.$or = [{ entityLabel: rx }, { byName: rx }, { action: rx }, { 'changes.field': rx }];
        }
        const ok = (d) => /^\d{4}-\d{2}-\d{2}$/.test(String(d || ''));
        if (ok(req.query.from) || ok(req.query.to)) {
            f.at = {};
            // dates are India dates (UTC+5:30)
            if (ok(req.query.from)) f.at.$gte = new Date(`${req.query.from}T00:00:00+05:30`);
            if (ok(req.query.to)) f.at.$lte = new Date(`${req.query.to}T23:59:59.999+05:30`);
        }
        const [rows, total] = await Promise.all([
            AuditLog.find(f).sort({ at: -1 }).skip((page - 1) * limit).limit(limit).lean(),
            AuditLog.countDocuments(f),
        ]);
        res.json({ success: true, data: rows, pagination: { page, limit, total, hasMore: page * limit < total } });
    } catch (e) { next(e); }
};
