const express = require('express');
const router = express.Router();
const {
    createItem,
    getItems,
    getItem,
    getItemByBarcode,
    updateItem,
    deleteItem,
    sellItem,
    removeTemporarily
} = require('../controllers/itemController');
const { protect, authorize } = require('../middleware/auth');

// All routes require authentication
router.use(protect);

// Public (authenticated) routes
router.get('/', getItems);
router.get('/barcode/:code', getItemByBarcode);
router.get('/:id', getItem);

// Staff and Admin routes
router.post('/', authorize('admin', 'staff'), createItem);
router.put('/:id', authorize('admin', 'staff'), updateItem);
router.put('/:id/sell', authorize('admin', 'staff'), sellItem);
router.put('/:id/remove-temporarily', authorize('admin', 'staff'), removeTemporarily);

// Admin only routes
router.delete('/:id', authorize('admin'), deleteItem);

module.exports = router;
