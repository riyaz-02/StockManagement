const express = require('express');
const router = express.Router();
const c = require('../controllers/oldMetalController');
const { protect, requirePermission } = require('../middleware/auth');

router.use(protect);
router.get('/', requirePermission('oldMetal.view'), c.list);
router.get('/available', requirePermission('billing.create'), c.available);
router.post('/calculate', requirePermission('oldMetal.view'), c.calculate);
router.post('/', requirePermission('oldMetal.create'), c.create);
router.post('/:id/cancel', requirePermission('oldMetal.create'), c.cancel);

module.exports = router;
