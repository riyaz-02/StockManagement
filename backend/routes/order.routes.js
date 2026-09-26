const express = require('express');
const router = express.Router();
const c = require('../controllers/orderController');
const { protect, requirePermission } = require('../middleware/auth');

router.use(protect);
router.get('/', requirePermission('orders.view'), c.list);
router.get('/:id', requirePermission('orders.view'), c.get);
router.post('/', requirePermission('orders.create'), c.create);
router.post('/:id/advance', requirePermission('orders.create'), c.addAdvance);
router.post('/:id/status', requirePermission('orders.create'), c.setStatus);
router.post('/:id/cancel', requirePermission('orders.cancel'), c.cancel);

module.exports = router;
