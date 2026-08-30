const express = require('express');
const router = express.Router();
const {
    getSettingsByCategory,
    getSettingByType,
    updateSetting,
    addValue,
    deleteValue,
    initializeSettings,
} = require('../controllers/settingsController');
const { protect, requirePermission, hasPermission } = require('../middleware/auth');

// Settings cover multiple domains (item/container/tag types) which map to
// different permission keys — pick the right one based on :category.
const CATEGORY_PERMISSION = {
    item: 'settings.manageItemTypes',
    container: 'settings.manageContainerTypes',
    tag: 'tags.manageSettings',
};

const requireSettingsPermission = () => async (req, res, next) => {
    const key = CATEGORY_PERMISSION[req.params.category];
    if (!key) {
        return res.status(400).json({ success: false, message: 'Invalid settings category' });
    }
    try {
        const allowed = await hasPermission(req.user, key);
        if (!allowed) {
            return res.status(403).json({
                success: false,
                message: `Not authorized — missing permission '${key}'`
            });
        }
        next();
    } catch (error) {
        res.status(500).json({ success: false, message: 'Server error while checking permissions' });
    }
};

// All routes require authentication
router.use(protect);

// Get settings by category (accessible to all authenticated users)
router.get('/:category', getSettingsByCategory);
router.get('/:category/:type', getSettingByType);

// Requires the permission matching the settings category being changed
router.post('/initialize', requirePermission('settings.manageItemTypes'), initializeSettings);
router.put('/:category/:type', requireSettingsPermission(), updateSetting);
router.post('/:category/:type/add', requireSettingsPermission(), addValue);
router.delete('/:category/:type/:value', requireSettingsPermission(), deleteValue);

module.exports = router;
