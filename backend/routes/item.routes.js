const express = require('express');
const router = express.Router();
const {
    createItem,
    getItems,
    getFilterOptions,
    getItem,
    getItemByBarcode,
    updateItem,
    deleteItem,
    sellItem,
    removeTemporarily,
    restoreItem,
    permanentDeleteItem,
    markAsNoSell,
    markAsActive
} = require('../controllers/itemController');
const { protect, authorize } = require('../middleware/auth');
const cloudinaryUpload = require('../middleware/cloudinaryUpload');

// All routes require authentication
router.use(protect);

// Public (authenticated) routes
router.get('/', getItems);
router.get('/filter-options', getFilterOptions);
router.get('/barcode/:code', getItemByBarcode);
router.get('/:id', getItem);

// Staff and Admin routes
router.post('/', authorize('admin', 'staff'), cloudinaryUpload.array('images', 5), createItem);
router.put('/:id', authorize('admin', 'staff'), cloudinaryUpload.array('images', 5), updateItem);
router.put('/:id/sell', authorize('admin', 'staff'), sellItem);
router.put('/:id/remove-temporarily', authorize('admin', 'staff'), removeTemporarily);
router.put('/:id/mark-no-sell', authorize('admin', 'staff'), markAsNoSell);
router.put('/:id/mark-active', authorize('admin', 'staff'), markAsActive);

// Admin only routes
router.delete('/:id', authorize('admin'), deleteItem);
router.put('/:id/restore', authorize('admin'), restoreItem);
router.delete('/:id/permanent', authorize('admin'), permanentDeleteItem);

module.exports = router;
