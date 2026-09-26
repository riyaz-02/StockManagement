'use strict';
const Rate = require('../models/AppRate');
const Calc = require('../services/billingCalc');

const view = (d) => ({
    gold: d ? d.gold || 0 : 0,
    silver: d ? d.silver || 0 : 0,
    updatedAt: d ? d.updatedAt || null : null,
    updatedByName: d ? d.updatedByName || '' : '',
    updatedToday: !!(d && d.updatedAt && Calc.todayIST(new Date(d.updatedAt)) === Calc.todayIST()),
    history: d && Array.isArray(d.history) ? d.history.slice(-10).reverse() : [],
});

// GET /api/rates : any signed-in user (bills, old metal and stock forms all start from these)
exports.get = async (req, res, next) => {
    try { res.json({ success: true, data: view(await Rate.findOne({ key: 'main' }).lean()) }); } catch (e) { next(e); }
};

// PUT /api/rates { gold?, silver? } [rates.edit]
exports.update = async (req, res, next) => {
    try {
        const b = req.body || {};
        const cur = (await Rate.findOne({ key: 'main' }).lean()) || {};
        const gold = b.gold === undefined || b.gold === '' ? cur.gold || 0 : Number(b.gold);
        const silver = b.silver === undefined || b.silver === '' ? cur.silver || 0 : Number(b.silver);
        // sanity limits catch a typing slip (an extra zero, a missing digit)
        if (!Number.isFinite(gold) || gold < 0 || (gold > 0 && (gold < 1000 || gold > 100000))) return res.status(400).json({ success: false, message: 'Gold rate per gram looks wrong (expected between 1,000 and 1,00,000)' });
        if (!Number.isFinite(silver) || silver < 0 || (silver > 0 && (silver < 10 || silver > 5000))) return res.status(400).json({ success: false, message: 'Silver rate per gram looks wrong (expected between 10 and 5,000)' });
        if (!(gold > 0) && !(silver > 0)) return res.status(400).json({ success: false, message: 'Enter the gold or the silver rate' });
        const by = req.user.name || '';
        const doc = await Rate.findOneAndUpdate(
            { key: 'main' },
            { $set: { gold: Math.round(gold * 100) / 100, silver: Math.round(silver * 100) / 100, updatedByName: by }, $push: { history: { $each: [{ at: new Date(), gold, silver, by }], $slice: -50 } }, $setOnInsert: { key: 'main' } },
            { upsert: true, new: true }).lean();
        res.json({ success: true, data: view(doc) });
    } catch (e) { next(e); }
};
