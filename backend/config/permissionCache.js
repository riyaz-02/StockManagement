/**
 * permissionCache.js — tiny in-memory cache of the 3 RolePermission docs
 * (manager/staff/viewer). The dataset is tiny and changes rarely, so a
 * plain in-process cache (refreshed on write, loaded lazily on first read)
 * is enough — no Redis/TTL needed.
 */

const { DEFAULT_GRIDS, CONFIGURABLE_ROLES } = require('./permissions');

let cache = null; // { manager: {key: bool}, staff: {...}, viewer: {...} }
let loadingPromise = null;

async function loadFromDb() {
    const RolePermission = require('../models/RolePermission');
    const docs = await RolePermission.find({});
    const grids = {};

    for (const role of CONFIGURABLE_ROLES) {
        const doc = docs.find(d => d.role === role);
        grids[role] = doc
            ? { ...doc.permissions }
            : { ...DEFAULT_GRIDS[role] };
    }

    cache = grids;
    return cache;
}

async function getGrids() {
    if (cache) return cache;
    if (!loadingPromise) {
        loadingPromise = loadFromDb().finally(() => {
            loadingPromise = null;
        });
    }
    return loadingPromise;
}

function invalidate() {
    cache = null;
}

module.exports = { getGrids, invalidate };
