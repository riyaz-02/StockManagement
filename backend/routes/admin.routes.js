const express = require('express');
const router = express.Router();
const { protect, authorize } = require('../middleware/auth');
const ctrl = require('../controllers/adminController');
const backup = require('../controllers/backupController');

// Admin/owner only (a role gate, not a permission someone could be handed: the backup exports every record). Read-only endpoints.
router.use(protect, authorize('admin', 'owner'));

router.get('/status', ctrl.status);
router.get('/audit', ctrl.audit);
router.post('/backup/inspect', backup.inspect);
router.post('/backup/download', backup.download);

module.exports = router;
