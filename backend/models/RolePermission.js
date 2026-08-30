/**
 * RolePermission.js — the checkbox grid for Manager/Staff/Viewer roles.
 * Admin/Owner have no document here — they bypass every permission check
 * in code (see middleware/auth.js requirePermission).
 */

const mongoose = require('mongoose');

const rolePermissionSchema = new mongoose.Schema(
    {
        role: {
            type: String,
            required: true,
            unique: true,
            enum: ['manager', 'staff', 'viewer'],
        },
        // Plain Mixed object, not a Mongoose Map — Map keys can't contain
        // "." and every permission key here is dot-namespaced.
        permissions: {
            type: mongoose.Schema.Types.Mixed,
            default: {},
        },
        updatedBy: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User',
        },
    },
    { timestamps: true }
);

module.exports = mongoose.model('RolePermission', rolePermissionSchema);
