const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/auth');
const ctrl = require('../controllers/gstController');

router.use(protect);

// GST configuration
router.get('/config', ctrl.getConfig);
router.put('/config', ctrl.updateConfig);

// Calculation
router.post('/calculate', ctrl.calculate);

// Validators
router.post('/validate-gstin', ctrl.validateGSTIN);
router.post('/validate-pan', ctrl.validatePAN);
router.post('/validate-hsn', ctrl.validateHSN);

module.exports = router;
