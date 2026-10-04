/**
 * Expense.js - the shop's running costs (rent, salary, tea, transport...) paid out of the till or the bank (collection app_expenses).
 * Branch-scoped like every stock / operations model. They feed the Day Book (money out).
 */
const mongoose = require('mongoose');

const CATEGORIES = ['Salary', 'Rent', 'Electricity', 'Tea / food', 'Transport', 'Repair / labour', 'Packing / tags', 'Advertising', 'Other'];
const MODES = ['Cash', 'Card', 'Online', 'Cheque'];

const schema = new mongoose.Schema(
    {
        date: { type: String, required: true, index: true },        // YYYY-MM-DD (India)
        amount: { type: Number, required: true, min: 0.01 },
        mode: { type: String, enum: MODES, default: 'Cash' },
        category: { type: String, enum: CATEGORIES, default: 'Other' },
        note: { type: String, trim: true, default: '' },
        status: { type: String, enum: ['active', 'cancelled'], default: 'active', index: true },
        cancelledByName: String,
        createdBy: String,
        createdByName: String,
    },
    { collection: 'app_expenses', timestamps: true }
);
schema.plugin(require('../utils/branchScope').branchPlugin, { counter: true }); // bills / money at a counter carry it
const Model = mongoose.models.AppExpense || mongoose.model('AppExpense', schema);
module.exports = Model;
module.exports.CATEGORIES = CATEGORIES;
module.exports.MODES = MODES;
