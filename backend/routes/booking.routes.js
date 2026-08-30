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
const { protect, requirePermission } = require('../middleware/auth');

router.use(protect);

router.route('/')
    .get(requirePermission('bookings.view'), getBookings)
    .post(requirePermission('bookings.create'), createBooking);

router.route('/:id')
    .get(requirePermission('bookings.view'), getBooking)
    .put(requirePermission('bookings.edit'), updateBooking);

router.put('/:id/cancel', requirePermission('bookings.cancel'), cancelBooking);
router.put('/:id/complete', requirePermission('bookings.complete'), completeBooking);

module.exports = router;
