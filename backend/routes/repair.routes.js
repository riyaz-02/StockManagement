const express = require('express');
const router = express.Router();
const {
    sendToRepair,
    returnFromRepair,
    getRepairItems,
    getRepairHistory
} = require('../controllers/repairController');
const { protect, requirePermission } = require('../middleware/auth');

// All routes require authentication
router.use(protect);

router.get('/', requirePermission('repair.view'), getRepairItems);
router.get('/history/:itemId', requirePermission('repair.view'), getRepairHistory);

router.post('/send', requirePermission('repair.send'), sendToRepair);
router.post('/return', requirePermission('repair.return'), returnFromRepair);

module.exports = router;
