/**
 * BranchCounter.js - a billing counter (a till / desk) inside one branch. Collection `app_branch_counters`.
 *
 * A branch can have several counters ("Counter 1", "Gold desk", "Silver desk" ...). A person can be given a counter as their
 * default (users.counterId), the sign-in picks it up, and everything made while it is in force is stamped with it
 * (counterId / counterName on invoices, payments, estimates, orders ...), so sales and money can be followed per counter.
 * Counters are never deleted (old records point at them): they are switched off (isActive:false) instead.
 */
const mongoose = require('mongoose');

const schema = new mongoose.Schema(
    {
        name: { type: String, required: true, trim: true, maxlength: 40 },
        // a short label for receipts and reports (C1, GOLD ...)
        code: { type: String, trim: true, uppercase: true, maxlength: 10, default: '' },
        note: { type: String, trim: true, maxlength: 120, default: '' },
        isActive: { type: Boolean, default: true },
    },
    { collection: 'app_branch_counters', versionKey: false, timestamps: true }
);
// branchId, createdBy(+Name) and updatedBy(+Name) are added and stamped by the branch plugin
schema.plugin(require('../utils/branchScope').branchPlugin);
schema.index({ branchId: 1, name: 1 });

module.exports = mongoose.models.BranchCounter || mongoose.model('BranchCounter', schema);
