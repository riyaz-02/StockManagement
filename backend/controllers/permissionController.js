const RolePermission = require('../models/RolePermission');
const User = require('../models/User');
const { GROUPS, ALL_KEYS, DEFAULT_GRIDS, CONFIGURABLE_ROLES } = require('../config/permissions');
const permissionCache = require('../config/permissionCache');
const { hasPermission } = require('../middleware/auth');

const FULL_ACCESS_ROLES = ['admin', 'owner'];

// @desc    Get the full permission taxonomy (groups + keys + labels)
// @route   GET /api/permissions/definitions
// @access  Private
exports.getDefinitions = async (req, res) => {
    res.status(200).json({
        success: true,
        data: { groups: GROUPS, configurableRoles: CONFIGURABLE_ROLES }
    });
};

// @desc    Get the caller's own effective permission map
// @route   GET /api/permissions/me
// @access  Private
exports.getMyPermissions = async (req, res) => {
    try {
        if (FULL_ACCESS_ROLES.includes(req.user.role)) {
            return res.status(200).json({
                success: true,
                data: { all: true, permissions: {} }
            });
        }

        const grids = await permissionCache.getGrids();
        const roleGrid = grids[req.user.role] || {};
        const permissions = {};

        for (const key of ALL_KEYS) {
            permissions[key] = await hasPermission(req.user, key);
        }

        res.status(200).json({
            success: true,
            data: { all: false, permissions, roleDefaults: roleGrid }
        });
    } catch (error) {
        console.error('Get my permissions error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while fetching permissions'
        });
    }
};

// @desc    Get all role permission grids (admin/owner only)
// @route   GET /api/permissions/roles
// @access  Private/Admin
exports.getRoleGrids = async (req, res) => {
    try {
        const grids = await permissionCache.getGrids();
        res.status(200).json({
            success: true,
            data: { grids }
        });
    } catch (error) {
        console.error('Get role grids error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while fetching role permissions'
        });
    }
};

// @desc    Update one role's permission grid (admin/owner only)
// @route   PUT /api/permissions/roles/:role
// @access  Private/Admin
exports.updateRoleGrid = async (req, res) => {
    try {
        const { role } = req.params;
        const { permissions } = req.body;

        if (!CONFIGURABLE_ROLES.includes(role)) {
            return res.status(400).json({
                success: false,
                message: `Role must be one of: ${CONFIGURABLE_ROLES.join(', ')}`
            });
        }

        if (!permissions || typeof permissions !== 'object') {
            return res.status(400).json({
                success: false,
                message: 'Please provide a permissions object'
            });
        }

        const unknownKeys = Object.keys(permissions).filter(k => !ALL_KEYS.includes(k));
        if (unknownKeys.length > 0) {
            return res.status(400).json({
                success: false,
                message: `Unknown permission key(s): ${unknownKeys.join(', ')}`
            });
        }

        // Merge onto existing defaults so a partial update doesn't blank out
        // unspecified keys.
        const existing = await RolePermission.findOne({ role });
        const mergedPermissions = {
            ...(existing ? existing.permissions : DEFAULT_GRIDS[role]),
            ...permissions
        };

        const updated = await RolePermission.findOneAndUpdate(
            { role },
            { role, permissions: mergedPermissions, updatedBy: req.user.id },
            { new: true, upsert: true, setDefaultsOnInsert: true }
        );

        permissionCache.invalidate();

        res.status(200).json({
            success: true,
            message: `Permissions updated for ${role}`,
            data: { grid: { ...updated.permissions } }
        });
    } catch (error) {
        console.error('Update role grid error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while updating role permissions'
        });
    }
};

// @desc    Set/clear one user's permission overrides (admin/owner only)
// @route   PUT /api/users/:id/permission-overrides
// @access  Private/Admin
exports.updateUserOverrides = async (req, res) => {
    try {
        const { overrides } = req.body;

        if (!overrides || typeof overrides !== 'object') {
            return res.status(400).json({
                success: false,
                message: 'Please provide an overrides object'
            });
        }

        const unknownKeys = Object.keys(overrides).filter(k => !ALL_KEYS.includes(k));
        if (unknownKeys.length > 0) {
            return res.status(400).json({
                success: false,
                message: `Unknown permission key(s): ${unknownKeys.join(', ')}`
            });
        }

        const user = await User.findById(req.params.id);
        if (!user) {
            return res.status(404).json({
                success: false,
                message: 'User not found'
            });
        }

        if (FULL_ACCESS_ROLES.includes(user.role)) {
            return res.status(400).json({
                success: false,
                message: 'Admin/Owner accounts always have full access and cannot be individually restricted'
            });
        }

        const nextOverrides = { ...(user.permissionOverrides || {}) };
        for (const [key, value] of Object.entries(overrides)) {
            if (value === null) {
                delete nextOverrides[key];
            } else {
                nextOverrides[key] = !!value;
            }
        }
        user.permissionOverrides = nextOverrides;
        user.markModified('permissionOverrides');

        await user.save();

        res.status(200).json({
            success: true,
            message: 'Permission overrides updated',
            data: { permissionOverrides: { ...user.permissionOverrides } }
        });
    } catch (error) {
        console.error('Update user overrides error:', error);
        res.status(500).json({
            success: false,
            message: 'Server error while updating user permission overrides'
        });
    }
};
