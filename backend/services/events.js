/**
 * events.js - the realtime spine shared by the app and the website.
 *
 *   emit('rate.changed', { gold, silver }, { branchId, roles, userIds, module, actor })
 *        -> saved as an event with a rising number, and pushed at once to everyone connected who may see it
 *   subscribe(client)  -> a live connection (Server-Sent Events, see controllers/liveController.js)
 *   since(n, viewer)   -> what a client missed (catch-up after being offline)
 *
 * Who may see an event (visible()): the branch matches (or the viewer sees every branch) AND the audience matches
 * (roles / userIds empty = everyone). A viewer is { id, role, restrict } where restrict = null (all branches) or a list.
 * emit() never throws and never waits for the network: a problem here must never break a bill.
 */
'use strict';
const mongoose = require('mongoose');
const AppEvent = require('../models/AppEvent');
const logger = require('../config/logger');

const TYPES = ['rate.changed', 'settings.changed', 'permissions.changed', 'app.update', 'notification.new', 'data.changed'];
const clients = new Map();          // id -> { id, res, viewer }
let nextClientId = 1;
const MAX_PER_USER = 5;

/** Can this viewer see this event? (pure: unit tested) */
function visible(ev, viewer) {
    const branchOk = !viewer.restrict || ev.branchId === 'all' || viewer.restrict.includes(ev.branchId || 'main');
    if (!branchOk) return false;
    const a = ev.audience || {};
    const roles = a.roles || [], ids = a.userIds || [];
    if (!roles.length && !ids.length) return true;
    return roles.includes(viewer.role) || ids.includes(String(viewer.id));
}

const wire = (ev) => ({ seq: ev.seq, type: ev.type, module: ev.module || '', data: ev.data || {}, by: ev.actorName || '', at: ev.at });

async function nextSeq() {
    const r = await mongoose.connection.collection('app_counters').findOneAndUpdate({ _id: 'events' }, { $inc: { seq: 1 } }, { upsert: true, returnDocument: 'after' });
    return (r && (r.seq !== undefined ? r.seq : r.value && r.value.seq)) || 1;
}

/** Write the event and push it to the connected people who may see it. Fire and forget. */
function emit(type, data = {}, opts = {}) {
    (async () => {
        try {
            const actor = opts.actor || {};
            const ev = await AppEvent.create({
                seq: await nextSeq(), type, module: opts.module || '', branchId: opts.branchId || 'all',
                audience: { roles: opts.roles || [], userIds: (opts.userIds || []).map(String) },
                data: JSON.parse(JSON.stringify(data || {})), actorId: String(actor.id || ''), actorName: String(actor.name || ''),
            });
            const payload = ev.toObject();
            for (const c of clients.values()) {
                if (visible(payload, c.viewer)) write(c, payload);
            }
        } catch (err) {
            logger.warn(`[events] could not record ${type}: ${err.message}`);
        }
    })();
}

/** A change in a module's data (lists on the other screens refresh themselves). */
const changed = (module, branchId, actor) => emit('data.changed', { module }, { module, branchId: branchId || 'all', actor });

function write(c, ev) {
    try {
        c.res.write(`id: ${ev.seq}\nevent: ${ev.type}\ndata: ${JSON.stringify(wire(ev))}\n\n`);
    } catch (_) { /* the connection is closing; its close handler removes it */ }
}

/** Register a live connection. Returns a function that removes it. A person keeps at most MAX_PER_USER connections. */
function subscribe(res, viewer) {
    const mine = [...clients.values()].filter((c) => String(c.viewer.id) === String(viewer.id));
    while (mine.length >= MAX_PER_USER) {
        const old = mine.shift();
        try { old.res.end(); } catch (_) { /* already gone */ }
        clients.delete(old.id);
    }
    const c = { id: nextClientId++, res, viewer };
    clients.set(c.id, c);
    return () => clients.delete(c.id);
}

/** Events after `seq` that this viewer may see, oldest first. reset = the gap is older than what we keep: refresh everything. */
async function since(seq, viewer, limit = 300) {
    const n = Math.max(0, Number(seq) || 0);
    const latestDoc = await AppEvent.findOne().sort({ seq: -1 }).select('seq').lean();
    const oldestDoc = await AppEvent.findOne().sort({ seq: 1 }).select('seq').lean();
    const latest = latestDoc ? latestDoc.seq : 0;
    const reset = n > 0 && oldestDoc ? n < oldestDoc.seq - 1 : false;
    if (n >= latest) return { events: [], latest, reset: false };
    const rows = await AppEvent.find({ seq: { $gt: n } }).sort({ seq: 1 }).limit(limit * 3).lean();
    const events = rows.filter((e) => visible(e, viewer)).slice(0, limit).map(wire);
    return { events, latest, reset };
}

// ── one-time tickets: lets a browser open the live channel without ever holding the login token ──
const tickets = new Map();          // ticket -> { viewer, exp }
function issueTicket(viewer) {
    const t = require('crypto').randomBytes(24).toString('hex');
    tickets.set(t, { viewer, exp: Date.now() + 60000 });
    for (const [k, v] of tickets) if (v.exp < Date.now()) tickets.delete(k);
    return t;
}
function consumeTicket(t) {
    const v = tickets.get(String(t || ''));
    if (!v) return null;
    tickets.delete(t);
    return v.exp >= Date.now() ? v.viewer : null;
}

const connected = () => clients.size;

module.exports = { TYPES, visible, wire, emit, changed, subscribe, since, issueTicket, consumeTicket, connected };
