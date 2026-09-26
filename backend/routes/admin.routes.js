const express = require('express');
const router = express.Router();
const { protect, authorize } = require('../middleware/auth');
const ctrl = require('../controllers/adminController');

// Admin/owner only. Read-only endpoints.
router.use(protect, authorize('admin', 'owner'));

router.get('/status', ctrl.status);

module.exports = router;
