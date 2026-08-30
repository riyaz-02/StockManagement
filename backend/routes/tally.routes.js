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
const { protect, requirePermission } = require('../middleware/auth');

// All routes require authentication
router.use(protect);

router.get('/', requirePermission('tally.view'), getTallySessions);
router.get('/:id', requirePermission('tally.view'), getTallySession);
router.get('/:id/report', requirePermission('tally.view'), getTallyReport);
router.get('/:id/items', requirePermission('tally.view'), getTallyItems);

router.post('/', requirePermission('tally.create'), createTally);
router.put('/:id/scan', requirePermission('tally.scan'), scanItem);
router.put('/:id/verify-weight', requirePermission('tally.scan'), verifyWeight);
router.put('/:id/lock', requirePermission('tally.lock'), lockTally);
router.post('/:id/add-item', requirePermission('tally.addItem'), addItemToTally);
router.post('/:id/update-inventory', requirePermission('tally.updateInventory'), updateInventory);
router.delete('/:id', requirePermission('tally.deleteSession'), deleteTally);

router.put('/:id/remove-item', requirePermission('tally.removeItem'), removeUnscannedItem);
router.put('/:id/remove-unscanned', requirePermission('tally.removeItem'), removeAllUnscannedItems);

module.exports = router;
