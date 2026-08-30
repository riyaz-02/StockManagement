const express = require('express');
const router = express.Router();
const {
    getInventorySnapshots,
    getInventorySnapshot
} = require('../controllers/inventoryController');
const { protect, requirePermission } = require('../middleware/auth');

// All routes require authentication
router.use(protect);

router.get('/', requirePermission('tally.view'), getInventorySnapshots);
router.get('/:id', requirePermission('tally.view'), getInventorySnapshot);

module.exports = router;
