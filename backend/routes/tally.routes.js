const express = require('express');
const router = express.Router();
const {
    startTally,
    scanItemInTally,
    lockTally,
    getTallySession,
    getTallySessions
} = require('../controllers/tallyController');
const { protect, authorize } = require('../middleware/auth');

// All routes require authentication
router.use(protect);

// Public (authenticated) routes
router.get('/', getTallySessions);
router.get('/:id', getTallySession);

// Staff and Admin routes
router.post('/start', authorize('admin', 'staff'), startTally);
router.post('/scan', authorize('admin', 'staff'), scanItemInTally);
router.post('/lock', authorize('admin', 'staff'), lockTally);

module.exports = router;
