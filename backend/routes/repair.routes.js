const express = require('express');
const router = express.Router();
const {
    sendToRepair,
    returnFromRepair,
    getRepairItems,
    getRepairHistory
} = require('../controllers/repairController');
const { protect, authorize } = require('../middleware/auth');

// All routes require authentication
router.use(protect);

// Public (authenticated) routes
router.get('/', getRepairItems);
router.get('/history/:itemId', getRepairHistory);

// Staff and Admin routes
router.post('/send', authorize('admin', 'staff'), sendToRepair);
router.post('/return', authorize('admin', 'staff'), returnFromRepair);

module.exports = router;
