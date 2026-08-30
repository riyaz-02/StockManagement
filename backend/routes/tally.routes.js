const express = require('express');
const router = express.Router();
const {
    createTally,
    getTallySessions,
    getTallySession,
    scanItem,
    verifyWeight,
    lockTally,
    getTallyReport,
    getTallyItems,
    deleteTally,
    removeUnscannedItem,
    removeAllUnscannedItems,
    addItemToTally,
    updateInventory
} = require('../controllers/tallyController');
const { protect, authorize } = require('../middleware/auth');

// All routes require authentication
router.use(protect);

// Public (authenticated) routes
router.get('/', getTallySessions);
router.get('/:id', getTallySession);
router.get('/:id/report', getTallyReport);
router.get('/:id/items', getTallyItems);

// Staff and Admin routes
router.post('/', authorize('admin', 'staff'), createTally);
router.put('/:id/scan', authorize('admin', 'staff'), scanItem);
router.put('/:id/verify-weight', authorize('admin', 'staff'), verifyWeight);
router.put('/:id/lock', authorize('admin', 'staff'), lockTally);
router.post('/:id/add-item', authorize('admin', 'staff'), addItemToTally);
router.post('/:id/update-inventory', authorize('admin', 'staff'), updateInventory);
router.delete('/:id', authorize('admin'), deleteTally);

// Admin-only cleanup routes (deleting stock is a bigger deal than scanning it)
router.put('/:id/remove-item', authorize('admin'), removeUnscannedItem);
router.put('/:id/remove-unscanned', authorize('admin'), removeAllUnscannedItems);

module.exports = router;
