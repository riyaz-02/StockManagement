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
    removeTemporarily,
    restoreItem,
    permanentDeleteItem,
    markAsNoSell,
    markAsActive
} = require('../controllers/itemController');
const { protect, requirePermission } = require('../middleware/auth');
const { mediaUpload, MB } = require('../middleware/mediaUpload');
const cloudinaryUpload = mediaUpload({ allow: ['image'], maxBytes: 12 * MB, folder: () => 'items' });

// All routes require authentication
router.use(protect);

// Public (authenticated) routes
router.get('/', requirePermission('items.view'), getItems);
router.get('/filter-options', requirePermission('items.view'), getFilterOptions);
router.get('/barcode/:code', requirePermission('items.view'), getItemByBarcode);
router.get('/:id', requirePermission('items.view'), getItem);

router.post('/', requirePermission('items.create'), cloudinaryUpload.array('images', 5), createItem);
router.put('/:id', requirePermission('items.edit'), cloudinaryUpload.array('images', 5), updateItem);
router.put('/:id/remove-temporarily', requirePermission('items.edit'), removeTemporarily);
router.put('/:id/mark-no-sell', requirePermission('items.edit'), markAsNoSell);
router.put('/:id/mark-active', requirePermission('items.edit'), markAsActive);

router.delete('/:id', requirePermission('items.delete'), deleteItem);
router.put('/:id/restore', requirePermission('items.restore'), restoreItem);
router.delete('/:id/permanent', requirePermission('items.permanentDelete'), permanentDeleteItem);

module.exports = router;
