const express = require('express');
const router = express.Router();
const {
    createContainer,
    getContainers,
    getContainer,
    updateContainer,
    deleteContainer,
    findBestSlot,
    uploadImage
} = require('../controllers/containerController');
const { protect, authorize } = require('../middleware/auth');
const cloudinaryUpload = require('../middleware/cloudinaryUpload');

// All routes require authentication
router.use(protect);

// Upload route
router.post('/upload', authorize('admin', 'staff'), cloudinaryUpload.single('image'), uploadImage);

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
