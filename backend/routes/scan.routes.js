const express = require('express');
const router = express.Router();
const { scanBarcode, lookupBarcode } = require('../controllers/scanController');
const { protect } = require('../middleware/auth');

// All routes are protected
router.use(protect);

router.post('/', scanBarcode);
router.get('/lookup/:barcode', lookupBarcode);

module.exports = router;
