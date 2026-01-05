const express = require('express');
const router = express.Router();
const {
    createOutwardMovement,
    returnItem,
    getItemMovements,
    getOutwardMovements,
    getOutwardMovement
} = require('../controllers/outwardMovementController');
const { protect, authorize } = require('../middleware/auth');

// All routes require authentication
router.use(protect);

// Staff and Admin routes
router.post('/', authorize('admin', 'staff'), createOutwardMovement);
router.get('/', authorize('admin', 'staff'), getOutwardMovements);
router.get('/:id', authorize('admin', 'staff'), getOutwardMovement);
router.get('/item/:itemId', authorize('admin', 'staff'), getItemMovements);
router.put('/:id/return', authorize('admin', 'staff'), returnItem);

module.exports = router;
