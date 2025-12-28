const express = require('express');
const router = express.Router();
const {
    createBooking,
    getBookings,
    getBooking,
    cancelBooking,
    completeBooking
} = require('../controllers/bookingController');
const { protect, authorize } = require('../middleware/auth');

// All routes require authentication
router.use(protect);

// Public (authenticated) routes
router.get('/', getBookings);
router.get('/:id', getBooking);

// Staff and Admin routes
router.post('/', authorize('admin', 'staff'), createBooking);
router.put('/:id/cancel', authorize('admin', 'staff'), cancelBooking);
router.put('/:id/complete', authorize('admin', 'staff'), completeBooking);

module.exports = router;
