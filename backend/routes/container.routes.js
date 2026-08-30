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
const { protect, requirePermission } = require('../middleware/auth');
const cloudinaryUpload = require('../middleware/cloudinaryUpload');

// All routes require authentication
router.use(protect);

router.post('/upload', requirePermission('containers.edit'), cloudinaryUpload.single('image'), uploadImage);

router.get('/', requirePermission('containers.view'), getContainers);
router.get('/:id', requirePermission('containers.view'), getContainer);
router.post('/find-slot', requirePermission('items.edit'), findBestSlot);

router.post('/', requirePermission('containers.create'), createContainer);
router.put('/:id', requirePermission('containers.edit'), updateContainer);

router.delete('/:id', requirePermission('containers.delete'), deleteContainer);

module.exports = router;
