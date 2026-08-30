const express = require('express');
const router = express.Router();
const { scanBarcode, lookupBarcode } = require('../controllers/scanController');
const { protect, requirePermission } = require('../middleware/auth');

// All routes are protected
router.use(protect);

router.post('/', requirePermission('items.view'), scanBarcode);
router.get('/lookup/:barcode', requirePermission('items.view'), lookupBarcode);

module.exports = router;
