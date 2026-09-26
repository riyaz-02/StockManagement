const express = require('express');
const router = express.Router();
const c = require('../controllers/rateController');
const { protect, requirePermission } = require('../middleware/auth');

router.use(protect);
router.get('/', c.get);
router.put('/', requirePermission('rates.edit'), c.update);

module.exports = router;
