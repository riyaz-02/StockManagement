'use strict';
const presence = require('../services/presence');

// POST /api/presence/ping { platform: 'app'|'web', screen? } — any signed-in user, reports their own presence.
// Best-effort only: a ping is not part of any real workflow, so it must never turn into an error for the caller.
exports.ping = async (req, res) => {
    try { presence.touch(req.user, req.body || {}); } catch (e) { /* ignore */ }
    res.json({ success: true });
};

// GET /api/presence — who has the app or the website open right now (Staff & Roles > Live now).
exports.list = async (req, res, next) => {
    try {
        res.json({ success: true, data: presence.list() });
    } catch (e) { next(e); }
};
