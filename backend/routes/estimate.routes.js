const express = require('express');
const router = express.Router();
const c = require('../controllers/estimateController');
const { protect, requirePermission } = require('../middleware/auth');

router.use(protect);
router.get('/', requirePermission('estimates.view'), c.list);
router.get('/:id', requirePermission('estimates.view'), c.get);
router.post('/', requirePermission('estimates.create'), c.create);
router.post('/:id/converted', requirePermission('billing.create'), c.converted);
router.delete('/:id', requirePermission('estimates.create'), c.cancel);

module.exports = router;
