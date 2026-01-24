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
    removeTemporarily,
    restoreItem,
    permanentDeleteItem
} = require('../controllers/itemController');
const { protect, authorize } = require('../middleware/auth');
const cloudinaryUpload = require('../middleware/cloudinaryUpload');

// All routes require authentication
router.use(protect);

// Public (authenticated) routes
router.get('/', getItems);
router.get('/barcode/:code', getItemByBarcode);
router.get('/:id', getItem);

// Staff and Admin routes
router.post('/', authorize('admin', 'staff'), cloudinaryUpload.array('images', 5), createItem);
router.put('/:id', authorize('admin', 'staff'), cloudinaryUpload.array('images', 5), updateItem);
router.put('/:id/sell', authorize('admin', 'staff'), sellItem);
router.put('/:id/remove-temporarily', authorize('admin', 'staff'), removeTemporarily);

// Admin only routes
router.delete('/:id', authorize('admin'), deleteItem);
router.put('/:id/restore', authorize('admin'), restoreItem);
router.delete('/:id/permanent', authorize('admin'), permanentDeleteItem);

module.exports = router;
