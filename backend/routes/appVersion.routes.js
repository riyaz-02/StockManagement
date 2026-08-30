const express = require('express');
const router = express.Router();
const { getAppVersion, updateAppVersion } = require('../controllers/appVersionController');
const { protect, authorize } = require('../middleware/auth');

// Public — checked by the splash screen before login
router.get('/', getAppVersion);

// Admin only
router.put('/', protect, authorize('admin'), updateAppVersion);

module.exports = router;
