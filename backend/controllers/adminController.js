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
const { getShopmanageConnection, getLgpAdminConnection } = require('../config/db');
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
        return ['MONGODB_URI', 'SHOPMANAGE_DB_URI', 'LGP_ADMIN_DB_URI', 'JWT_SECRET'];
    }
}
const REQUIRED = new Set(['MONGODB_URI', 'SHOPMANAGE_DB_URI', 'JWT_SECRET']);

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
        const databases = await Promise.all([
            dbHealth('Main app DB', () => mongoose.connection, 'MONGODB_URI'),
            dbHealth('Store management DB', getShopmanageConnection, 'SHOPMANAGE_DB_URI'),
            dbHealth('LGP admin DB (directory)', getLgpAdminConnection, 'LGP_ADMIN_DB_URI'),
        ]);

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
