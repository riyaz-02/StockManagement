'use strict';
const Rules = require('../services/stockRules');
const Doc = require('../models/AppStockSettings');

exports.get = async (req, res, next) => {
    try {
        const stored = await Doc.findOne({ key: 'main' }).lean();
        res.json({ success: true, data: { settings: Rules.resolve(stored), defaults: Rules.defaults(), options: Rules.options(), updatedAt: stored ? stored.updatedAt : null, updatedByName: stored ? stored.updatedByName : '' } });
    } catch (e) { next(e); }
};

exports.update = async (req, res, next) => {
    try {
        const v = Rules.validate(req.body || {});
        if (v.error) return res.status(400).json({ success: false, message: v.error });
        if (!Object.keys(v.set).length) return res.status(400).json({ success: false, message: 'Nothing to change' });
        await Doc.updateOne({ key: 'main' }, { $set: { ...v.set, updatedBy: String(req.user._id), updatedByName: req.user.name || '' }, $setOnInsert: { key: 'main' } }, { upsert: true });
        const stored = await Doc.findOne({ key: 'main' }).lean();
        require('../services/audit').record(req, 'settings', 'stock', 'Stock Setting rules', 'changed', Object.keys(v.set).map((k) => ({ field: k, to: JSON.stringify(v.set[k]).slice(0, 180) })));
        require('../services/events').emit('settings.changed', { area: 'stock' }, { actor: { id: req.user._id, name: req.user.name } });
        res.json({ success: true, data: { settings: Rules.resolve(stored) } });
    } catch (e) { next(e); }
};

// POST /calculate: the same maths the stock form shows live (services/stockValuation.js), for other clients such as the website
exports.calculate = async (req, res, next) => {
    try {
        const stored = await Doc.findOne({ key: 'main' }).lean();
        res.json({ success: true, data: require('../services/stockValuation').computeStock(req.body || {}, Rules.resolve(stored)) });
    } catch (e) { next(e); }
};

exports.reset = async (req, res, next) => {
    try {
        await Doc.deleteOne({ key: 'main' });
        require('../services/audit').record(req, 'settings', 'stock', 'Stock Setting rules', 'reset to defaults', []);
        res.json({ success: true, data: { settings: Rules.defaults() } });
    } catch (e) { next(e); }
};
