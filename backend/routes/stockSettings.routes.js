const express = require('express');
const router = express.Router();
const c = require('../controllers/stockSettingsController');
const { protect, requirePermission } = require('../middleware/auth');

router.use(protect);
router.get('/', c.get);                                                              // every signed-in user (the forms follow these rules)
router.post('/calculate', c.calculate);
router.put('/', requirePermission('settings.manageStockRules'), c.update);
router.post('/reset', requirePermission('settings.manageStockRules'), c.reset);

module.exports = router;
