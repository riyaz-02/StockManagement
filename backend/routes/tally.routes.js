const express = require('express');
const router = express.Router();
const {
    createTally,
    getTallySessions,
    getTallySession,
    scanItem,
    lockTally,
    getTallyReport,
    getTallyItems
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
router.put('/:id/lock', authorize('admin', 'staff'), lockTally);

module.exports = router;
