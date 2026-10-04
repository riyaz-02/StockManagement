/**
 * counters.js - which billing counter a request works at (see models/BranchCounter.js).
 *
 * The counter of a request is, in this order: the `X-Counter` header (the person picked one on the billing screen), else the
 * counter assigned to them (users.counterId). It only counts when it belongs to the branch the request works on and is still
 * switched on; otherwise the request has no counter (records are then stamped with none, never with a wrong one).
 */
'use strict';

const BranchCounter = require('../models/BranchCounter');

const TTL_MS = 30 * 1000;
const cache = new Map(); // id -> { at, doc }

function validId(id) { return /^[a-f0-9]{24}$/i.test(String(id || '')); }

async function byId(id) {
    const key = String(id);
    const hit = cache.get(key);
    if (hit && Date.now() - hit.at < TTL_MS) return hit.doc;
    let doc = null;
    try { doc = await BranchCounter.findById(key).lean(); } catch (_) { /* not an id */ }
    cache.set(key, { at: Date.now(), doc });
    return doc;
}

/** Forget what is cached (after a counter was added / changed). */
function bust(id) { if (id) cache.delete(String(id)); else cache.clear(); }

const view = (c) => ({ counterId: String(c._id), counterName: c.name, counterCode: c.code || '' });

/** The first of `ids` that is a live counter of `branchId`, as { counterId, counterName, counterCode }, else null. */
async function pick(branchId, ...ids) {
    for (const id of ids) {
        if (!validId(id)) continue;
        const c = await byId(id);
        if (c && c.isActive !== false && String(c.branchId || 'main') === String(branchId || 'main')) return view(c);
    }
    return null;
}

/** For an assignment (a person's counter): the counter, or a 400 with the reason. '' / null clears it. */
async function resolveFor(branchId, id) {
    if (!id) return { counterId: '', counterName: '', counterCode: '' };
    const c = validId(id) ? await byId(id) : null;
    const fail = (msg) => { const e = new Error(msg); e.statusCode = 400; throw e; };
    if (!c) fail('Unknown counter');
    if (c.isActive === false) fail('That counter is switched off');
    if (String(c.branchId || 'main') !== String(branchId || 'main')) fail('That counter belongs to another branch');
    return view(c);
}

module.exports = { pick, resolveFor, bust, view, validId };
