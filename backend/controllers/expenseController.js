'use strict';
const Expense = require('../models/Expense');
const Calc = require('../services/billingCalc');
const { CATEGORIES, MODES } = Expense;

const ymd = (v) => (/^\d{4}-\d{2}-\d{2}$/.test(String(v || '')) ? String(v) : '');
const view = (d) => ({ id: String(d._id), date: d.date, amount: d.amount, mode: d.mode, category: d.category, note: d.note || '', status: d.status, createdByName: d.createdByName || '', createdAt: d.createdAt });

// GET /api/expenses?from=&to=  (default: today) -> { rows, total, categories, modes }
exports.list = async (req, res, next) => {
    try {
        const today = Calc.todayIST();
        const from = ymd(req.query.from) || today, to = ymd(req.query.to) || from;
        const rows = await Expense.find({ date: { $gte: from, $lte: to }, status: 'active' }).sort({ date: -1, createdAt: -1 }).limit(500).lean();
        const total = Math.round(rows.reduce((a, r) => a + r.amount, 0) * 100) / 100;
        res.json({ success: true, data: { from, to, rows: rows.map(view), total, categories: CATEGORIES, modes: MODES } });
    } catch (e) { next(e); }
};

// POST /api/expenses { amount, mode, category, note, date? }
exports.create = async (req, res, next) => {
    try {
        const b = req.body || {};
        const amount = Math.round(Number(b.amount) * 100) / 100;
        if (!(amount > 0)) return res.status(400).json({ success: false, message: 'Enter the amount' });
        if (amount > 10000000) return res.status(400).json({ success: false, message: 'That amount looks too large' });
        const mode = MODES.includes(b.mode) ? b.mode : 'Cash';
        const category = CATEGORIES.includes(b.category) ? b.category : 'Other';
        const today = Calc.todayIST();
        const date = ymd(b.date) || today;
        if (date > today) return res.status(400).json({ success: false, message: 'The date cannot be in the future' });
        const d = await Expense.create({ date, amount, mode, category, note: String(b.note || '').trim().slice(0, 200), createdBy: String(req.user._id), createdByName: req.user.name || '' });
        require('../services/events').changed('expenses', d.branchId, { id: req.user._id, name: req.user.name });
        require('../services/audit').record(req, 'expense', d._id, `${category} · ${date}`, 'recorded', [{ field: 'amount', to: String(amount) }, { field: 'mode', to: mode }]);
        res.status(201).json({ success: true, data: view(d.toObject()) });
    } catch (e) { next(e); }
};

// DELETE /api/expenses/:id : cancelled, never erased (the Day Book of that day changes, the record stays)
exports.cancel = async (req, res, next) => {
    try {
        const d = await Expense.findOneAndUpdate({ _id: req.params.id, status: 'active' }, { $set: { status: 'cancelled', cancelledByName: req.user.name || '' } }, { new: true }).lean();
        if (!d) return res.status(404).json({ success: false, message: 'Expense not found' });
        require('../services/events').changed('expenses', d.branchId, { id: req.user._id, name: req.user.name });
        require('../services/audit').record(req, 'expense', d._id, `${d.category} · ${d.date}`, 'cancelled', [{ field: 'amount', to: String(d.amount) }]);
        res.json({ success: true });
    } catch (e) { next(e); }
};
