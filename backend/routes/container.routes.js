const express = require('express');
const router = express.Router();
const {
    createContainer,
    getContainers,
    getContainer,
    updateContainer,
    deleteContainer,
    findBestSlot
} = require('../controllers/containerController');
const { protect, authorize } = require('../middleware/auth');

// All routes require authentication
router.use(protect);

// Public (authenticated) routes
router.get('/', getContainers);
router.get('/:id', getContainer);
router.post('/find-slot', findBestSlot);

// Admin/Staff routes
router.post('/', authorize('admin', 'staff'), createContainer);
router.put('/:id', authorize('admin', 'staff'), updateContainer);

// Admin only routes
router.delete('/:id', authorize('admin'), deleteContainer);

module.exports = router;
