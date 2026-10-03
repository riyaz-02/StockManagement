'use strict';
/** Wastage reports: see services/wastage.js for the rules (always pending first, approval counts, no self-approval). */
const W = require('../services/wastage');
const audit = require('../services/audit');

const handle = (res, e, fallback) => (e && e.status ? res.status(e.status).json({ success: false, message: e.message }) : (console.error('[Wastage]', e), res.status(500).json({ success: false, message: fallback })));
const label = (r) => `${r.metal} ${r.amount.toFixed(3)} g · ${r.category}`;

exports.list = async (req, res) => {
    try { res.json({ success: true, data: await W.list(req.query) }); } catch (e) { handle(res, e, 'Error fetching wastage reports'); }
};

exports.get = async (req, res) => {
    try {
        const r = await W.get(req.params.id);
        if (!r) return res.status(404).json({ success: false, message: 'Wastage report not found' });
        res.json({ success: true, data: { report: r } });
    } catch (e) { handle(res, e, 'Error fetching the wastage report'); }
};

exports.create = async (req, res) => {
    try {
        const r = await W.create(req.body || {}, req.user);
        audit.record(req, 'wastage', r._id, label(r), 'reported', [{ field: 'weight', to: `${r.amount.toFixed(3)} g` }, { field: 'category', to: r.category }]);
        res.status(201).json({ success: true, message: 'Wastage reported: it counts once it is approved', data: { report: r } });
    } catch (e) { handle(res, e, 'Error saving the wastage report'); }
};

exports.update = async (req, res) => {
    try {
        const r = await W.update(req.params.id, req.body || {}, req.user);
        audit.record(req, 'wastage', r._id, label(r), 'changed', []);
        res.json({ success: true, message: 'Wastage report updated', data: { report: r } });
    } catch (e) { handle(res, e, 'Error updating the wastage report'); }
};

exports.approve = async (req, res) => {
    try {
        const r = await W.approve(req.params.id, (req.body || {}).comment, req.user);
        audit.record(req, 'wastage', r._id, label(r), 'approved', [{ field: 'weight', to: `${r.amount.toFixed(3)} g` }]);
        res.json({ success: true, message: 'Wastage approved: it now counts in the metal balance', data: { report: r } });
    } catch (e) { handle(res, e, 'Error approving the wastage report'); }
};

exports.reject = async (req, res) => {
    try {
        const r = await W.reject(req.params.id, (req.body || {}).comment, req.user);
        audit.record(req, 'wastage', r._id, label(r), 'rejected', [{ field: 'why', to: r.comment }]);
        res.json({ success: true, message: 'Wastage rejected: it does not count', data: { report: r } });
    } catch (e) { handle(res, e, 'Error rejecting the wastage report'); }
};
