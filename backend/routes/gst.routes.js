const express = require('express');
const router = express.Router();
const { protect, requirePermission } = require('../middleware/auth');
const ctrl = require('../controllers/gstController');

router.use(protect);

// GST configuration
router.get('/config', requirePermission('gst.viewConfig'), ctrl.getConfig);
router.put('/config', requirePermission('gst.editConfig'), ctrl.updateConfig);

// Calculation — a pure utility, not tied to any stored config, safe for
// anyone who can at least view GST data.
router.post('/calculate', requirePermission('gst.viewConfig'), ctrl.calculate);

// Validators — same, stateless utilities.
router.post('/validate-gstin', requirePermission('gst.viewConfig'), ctrl.validateGSTIN);
router.post('/validate-pan', requirePermission('gst.viewConfig'), ctrl.validatePAN);
router.post('/validate-hsn', requirePermission('gst.viewConfig'), ctrl.validateHSN);

module.exports = router;
