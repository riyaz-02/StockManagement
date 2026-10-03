/**
 * presence.js — who has the app or the website open right now, and roughly where in it.
 *
 * Deliberately in memory, not a collection: this is throwaway, second-by-second state (a ping every ~20s from
 * whichever screens choose to send one), and it's fine to lose it on a restart. Never blocks or fails a request.
 */
'use strict';

const STALE_MS = 90 * 1000; // no ping in 90s -> treated as gone (a closed tab/app never says goodbye)

const byUser = new Map();

function touch(user, info) {
    if (!user || !user._id) return;
    const platform = info && info.platform === 'web' ? 'web' : 'app';
    byUser.set(String(user._id), {
        id: String(user._id),
        name: user.name || '',
        mobile: user.mobile || '',
        role: user.role || '',
        branchId: user.branchId || 'main',
        branchName: user.branchName || '',
        platform,
        screen: String((info && info.screen) || '').slice(0, 60),
        lastSeenAt: Date.now(),
    });
}

function list() {
    const now = Date.now();
    const out = [];
    for (const [id, v] of byUser) {
        if (now - v.lastSeenAt > STALE_MS) { byUser.delete(id); continue; }
        out.push({ ...v, secondsAgo: Math.round((now - v.lastSeenAt) / 1000) });
    }
    out.sort((a, b) => b.lastSeenAt - a.lastSeenAt);
    return out;
}

module.exports = { touch, list };
