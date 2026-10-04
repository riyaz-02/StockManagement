const express = require('express');
const router = express.Router();
const { getAppVersion, updateAppVersion, updateMaintenanceMode, getAdminView, uploadApk, publishApk, discardStaged, downloadApk } = require('../controllers/appVersionController');
const { protect, requirePermission } = require('../middleware/auth');

// Public — checked by the splash screen before login
router.get('/', getAppVersion);
router.get('/download', downloadApk);          // the published APK itself (public, resumable)

router.get('/admin', protect, requirePermission('appUpdate.manage'), getAdminView);
router.post('/upload', protect, requirePermission('appUpdate.manage'), uploadApk);
router.post('/publish', protect, requirePermission('appUpdate.manage'), publishApk);
router.delete('/staged', protect, requirePermission('appUpdate.manage'), discardStaged);
router.put('/', protect, requirePermission('appUpdate.manage'), updateAppVersion);
router.put('/maintenance', protect, requirePermission('appUpdate.manage'), updateMaintenanceMode);

module.exports = router;
