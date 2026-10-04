/**
 * Branch.js — a shop / branch of the business. Collection `app_branches` in
 * the app's own database (not the shared LGP cluster).
 *
 * Multi-branch groundwork: users belong to a branch (User.branchId) and every
 * record created through the User Directory is filed under the creating
 * user's branch. Data that predates branches maps to the built-in virtual
 * branch "main" (see utils/branches.js), which is never stored.
 */
const mongoose = require('mongoose');

const branchSchema = new mongoose.Schema(
    {
        name: { type: String, required: true, trim: true },
        code: { type: String, trim: true },
        // Letters put in front of this branch's invoice numbers (e.g. 'BR2' -> BR2-1). Main branch uses none.
        invoicePrefix: { type: String, trim: true, uppercase: true },
        city: { type: String, trim: true },
        state: { type: String, trim: true },
        phone: { type: String, trim: true },
        address: { type: String, trim: true },
        gstin: { type: String, trim: true, uppercase: true },
        isActive: { type: Boolean, default: true },
        createdBy: String,
        createdByName: String,
        updatedBy: String,
        updatedByName: String,
    },
    { collection: 'app_branches', versionKey: false, timestamps: true }
);

module.exports = mongoose.models.AppBranch || mongoose.model('AppBranch', branchSchema);
