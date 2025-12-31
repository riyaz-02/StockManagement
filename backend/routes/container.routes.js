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
const multer = require('multer');
const path = require('path');

// Configure Multer for image upload
const storage = multer.diskStorage({
    destination: function (req, file, cb) {
        cb(null, 'uploads/');
    },
    filename: function (req, file, cb) {
        cb(null, 'container-' + Date.now() + path.extname(file.originalname));
    }
});

const upload = multer({
    storage: storage,
    limits: { fileSize: 5000000 }, // 5MB limit
    fileFilter: function (req, file, cb) {
        console.log('Uploading file:', file.originalname, 'Mimetype:', file.mimetype);

        const filetypes = /jpeg|jpg|png|webp/;
        const extname = filetypes.test(path.extname(file.originalname).toLowerCase());
        const mimetype = filetypes.test(file.mimetype);
        const isOctet = file.mimetype === 'application/octet-stream';

        if ((mimetype || isOctet) && extname) {
            return cb(null, true);
        } else {
            console.error('File upload rejected:', file.mimetype, path.extname(file.originalname));
            cb(new Error('Images Only! Received: ' + file.mimetype));
        }
    }
});

// All routes require authentication
router.use(protect);

// Upload route
router.post('/upload', authorize('admin', 'staff'), upload.single('image'), uploadImage);

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
