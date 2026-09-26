/**
 * AuditLog.js — who changed what, and when. Collection `app_audit_log` in the
 * app's own database.
 *
 * The User Directory writes one entry for every EDIT of a customer, supplier,
 * karigar or staff profile, with a field-by-field before/after. Because edits
 * touch production data shared with the legacy web admin, this is the safety
 * net: any change can be traced and reverted by hand.
 */
const mongoose = require('mongoose');

const schema = new mongoose.Schema(
    {
        entity: { type: String, required: true, index: true },      // customer | supplier | karigar | staff
        entityId: { type: String, required: true, index: true },
        entityLabel: String,                                          // name at the time of the change
        action: { type: String, default: 'update' },
        by: String,
        byName: String,
        branchId: String,
        changes: [{ _id: false, field: String, from: String, to: String }],
        at: { type: Date, default: Date.now, index: true },
    },
    { collection: 'app_audit_log', versionKey: false }
);

module.exports = mongoose.models.AppAuditLog || mongoose.model('AppAuditLog', schema);
