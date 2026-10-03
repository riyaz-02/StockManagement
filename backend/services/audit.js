/**
 * audit.js - one line in the audit log for an admin action (who changed what, when).
 * Same collection as the User Directory's field-by-field edit log (`app_audit_log`), so the website reads them all in one list.
 * Never throws: the action already happened, a failed log line must not fail the request.
 */
'use strict';
const AuditLog = require('../models/AuditLog');

/** record(req, 'user', id, 'Ravi (9000000011)', 'created', [{ field: 'role', from: '', to: 'staff' }]) */
async function record(req, entity, entityId, label, action, changes = []) {
    try {
        await AuditLog.create({
            entity, entityId: String(entityId || ''), entityLabel: String(label || '').slice(0, 160), action,
            by: req.user ? String(req.user._id || req.user.id) : '', byName: (req.user && req.user.name) || '',
            branchId: (req.branchScope && req.branchScope.branchId) || undefined,
            changes: changes.map((c) => ({ field: String(c.field), from: c.from == null ? '' : String(c.from).slice(0, 200), to: c.to == null ? '' : String(c.to).slice(0, 200) })),
        });
    } catch (e) {
        console.error('[audit] could not write the log line:', e.message);
    }
}

module.exports = { record };
