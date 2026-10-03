const express = require('express');
const router = express.Router();
const { getAppVersion, updateAppVersion, updateMaintenanceMode } = require('../controllers/appVersionController');
const { protect, requirePermission } = require('../middleware/auth');

// Public — checked by the splash screen before login
router.get('/', getAppVersion);

router.put('/', protect, requirePermission('appUpdate.manage'), updateAppVersion);
router.put('/maintenance', protect, requirePermission('appUpdate.manage'), updateMaintenanceMode);

module.exports = router;
