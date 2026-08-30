const jwt = require('jsonwebtoken');
const User = require('../models/User');
const permissionCache = require('../config/permissionCache');

const FULL_ACCESS_ROLES = ['admin', 'owner'];

// Protect routes - verify JWT token
exports.protect = async (req, res, next) => {
    try {
        let token;

        // Check for token in Authorization header
        if (req.headers.authorization && req.headers.authorization.startsWith('Bearer')) {
            token = req.headers.authorization.split(' ')[1];
        }

        if (!token) {
            return res.status(401).json({
                success: false,
                message: 'Not authorized to access this route'
            });
        }

        try {
            // Verify token
            const decoded = jwt.verify(token, process.env.JWT_SECRET);

            // Get user from token
            req.user = await User.findById(decoded.id);

            if (!req.user) {
                return res.status(401).json({
                    success: false,
                    message: 'User not found'
                });
            }

            if (!req.user.isActive) {
                return res.status(401).json({
                    success: false,
                    message: 'User account is inactive'
                });
            }

            next();
        } catch (err) {
            return res.status(401).json({
                success: false,
                message: 'Invalid or expired token'
            });
        }
    } catch (error) {
        return res.status(500).json({
            success: false,
            message: 'Server error during authentication'
        });
    }
};

// Authorize specific roles
exports.authorize = (...roles) => {
    return (req, res, next) => {
        if (!roles.includes(req.user.role)) {
            return res.status(403).json({
                success: false,
                message: `User role '${req.user.role}' is not authorized to access this route`
            });
        }
        next();
    };
};

// Compute whether `user` has `key`, per the role-default + per-user-override
// resolution rules. Exported so the /api/permissions/me endpoint can reuse
// the exact same logic the middleware enforces.
exports.hasPermission = async (user, key) => {
    if (FULL_ACCESS_ROLES.includes(user.role)) return true;

    const override = user.permissionOverrides ? user.permissionOverrides[key] : undefined;
    if (override !== undefined) return override;

    const grids = await permissionCache.getGrids();
    const grid = grids[user.role];
    return grid ? !!grid[key] : false;
};

// Require a specific granular permission (see config/permissions.js).
// Must run after `protect` (needs req.user).
exports.requirePermission = (key) => {
    return async (req, res, next) => {
        try {
            const allowed = await exports.hasPermission(req.user, key);
            if (!allowed) {
                return res.status(403).json({
                    success: false,
                    message: `Not authorized — missing permission '${key}'`
                });
            }
            next();
        } catch (error) {
            res.status(500).json({
                success: false,
                message: 'Server error while checking permissions'
            });
        }
    };
};

// Generate JWT token
exports.generateToken = (userId) => {
    return jwt.sign({ id: userId }, process.env.JWT_SECRET, {
        expiresIn: process.env.JWT_EXPIRE || '7d'
    });
};
