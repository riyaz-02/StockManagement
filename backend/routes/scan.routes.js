const express = require('express');
const router = express.Router();
const { scanBarcode } = require('../controllers/scanController');
const { protect } = require('../middleware/auth');

// All routes require authentication
router.use(protect);

router.post('/', scanBarcode);

module.exports = router;
