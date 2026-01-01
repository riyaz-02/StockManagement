const express = require('express');
const router = express.Router();
const {
    createBooking,
    getBookings,
    getBooking,
    updateBooking,
    cancelBooking,
    completeBooking
} = require('../controllers/bookingController');
const { protect, authorize } = require('../middleware/auth');

router.use(protect);

router.route('/')
    .get(getBookings)
    .post(authorize('admin', 'staff'), createBooking);

router.route('/:id')
    .get(getBooking)
    .put(authorize('admin', 'staff'), updateBooking);

router.put('/:id/cancel', authorize('admin', 'staff'), cancelBooking);
router.put('/:id/complete', authorize('admin', 'staff'), completeBooking);

module.exports = router;
