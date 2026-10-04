const jwt = require('jsonwebtoken');
const User = require('../models/User');
const permissionCache = require('../config/permissionCache');
const { runWith } = require('../utils/branchScope');

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
            // (a person merged from the app's old list keeps their old id in legacyAppIds, so a phone still holding an old token works)
            req.user = (await User.findById(decoded.id)) || (await User.findOne({ legacyAppIds: String(decoded.id) }));

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

            // Which branch(es) this request works on (see utils/branchScope.js)
            const home = req.user.branchId || 'main';
            const all = await exports.canSeeAllBranches(req.user);
            const pick = String(req.headers['x-branch'] || '').trim();
            let restrict = all ? null : [home];
            let branchId = home;
            if (all && pick && pick !== 'all') { restrict = [pick]; branchId = pick; }
            // the billing counter in force: the one picked (X-Counter) or the person's own, if it belongs to this branch
            const counter = await require('../utils/counters').pick(branchId, String(req.headers['x-counter'] || '').trim(), req.user.counterId);
            req.branchScope = { branchId, restrict, all, counter };
            return runWith({
                branchId, restrict,
                counterId: counter ? counter.counterId : '', counterName: counter ? counter.counterName : '',
                userId: String(req.user._id), userName: req.user.name || req.user.username || '',
            }, () => next());
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

// May this user see the whole firm (every branch), not just their own?
exports.canSeeAllBranches = async (user) =>
    (await exports.hasPermission(user, 'branches.viewAll')) || (await exports.hasPermission(user, 'billing.viewAllBranches'));

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
// `expiresIn` overrides the default: the app asks for a long one (REMEMBER_EXPIRE) so a phone stays signed in.
exports.generateToken = (userId, expiresIn) => {
    return jwt.sign({ id: userId }, process.env.JWT_SECRET, {
        expiresIn: expiresIn || process.env.JWT_EXPIRE || '7d'
    });
};
exports.REMEMBER_EXPIRE = () => process.env.JWT_REMEMBER_EXPIRE || '90d';
