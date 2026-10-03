'use strict';
const Events = require('../services/events');

const viewerOf = (req) => ({ id: String(req.user._id), role: req.user.role, restrict: req.branchScope ? req.branchScope.restrict : [req.user.branchId || 'main'] });

// POST /api/live/ticket : a one-time 60-second ticket so a browser can open the live channel without the login token
exports.ticket = (req, res) => {
    res.json({ success: true, data: { ticket: Events.issueTicket(viewerOf(req)), expiresInSeconds: 60 } });
};

// GET /api/live/events?since=N : what was missed (used on start and after a gap)
exports.events = async (req, res, next) => {
    try {
        const r = await Events.since(req.query.since, viewerOf(req), Math.min(500, Number(req.query.limit) || 300));
        res.json({ success: true, data: r });
    } catch (e) { next(e); }
};

// GET /api/live?since=N  (Authorization header, or ?ticket=...) : the live stream (Server-Sent Events)
// First the events missed since N (if given), then every new one as it happens. A ": ping" comment every 25 s keeps proxies
// from closing it. The stream does NOT count as activity for the idle-stop, so an open screen never keeps the server awake.
exports.stream = async (req, res, next) => {
    try {
        const viewer = req.viewer || viewerOf(req);
        res.set({ 'Content-Type': 'text/event-stream; charset=utf-8', 'Cache-Control': 'no-cache, no-transform', Connection: 'keep-alive', 'X-Accel-Buffering': 'no' });
        res.flushHeaders();
        req.socket.setTimeout(0);
        req.socket.setKeepAlive(true);
        res.write('retry: 3000\n\n');

        const lastId = req.headers['last-event-id'];
        const since = req.query.since !== undefined ? req.query.since : lastId;
        const missed = await Events.since(since || 0, viewer);
        res.write(`event: hello\ndata: ${JSON.stringify({ latest: missed.latest, reset: missed.reset, serverTime: new Date().toISOString() })}\n\n`);
        if (since !== undefined) {
            for (const e of missed.events) res.write(`id: ${e.seq}\nevent: ${e.type}\ndata: ${JSON.stringify(e)}\n\n`);
        }

        const unsubscribe = Events.subscribe(res, viewer);
        const beat = setInterval(() => { try { res.write(': ping\n\n'); } catch (_) { /* closing */ } }, 25000);
        const done = () => { clearInterval(beat); unsubscribe(); };
        req.on('close', done);
        res.on('error', done);
    } catch (e) { next(e); }
};
