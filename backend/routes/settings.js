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
const { protect, authorize } = require('../middleware/auth');

// All routes require authentication
router.use(protect);

// Get settings by category (accessible to all authenticated users)
router.get('/:category', getSettingsByCategory);
router.get('/:category/:type', getSettingByType);

// Admin-only routes
router.post('/initialize', authorize('admin'), initializeSettings);
router.put('/:category/:type', authorize('admin'), updateSetting);
router.post('/:category/:type/add', authorize('admin'), addValue);
router.delete('/:category/:type/:value', authorize('admin'), deleteValue);

module.exports = router;
