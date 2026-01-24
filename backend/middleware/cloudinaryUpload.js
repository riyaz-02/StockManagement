const multer = require('multer');
const { CloudinaryStorage } = require('multer-storage-cloudinary');
const cloudinary = require('../config/cloudinary');

// Configure Cloudinary storage for multer
const storage = new CloudinaryStorage({
    cloudinary: cloudinary,
    params: async (req, file) => {
        // Determine folder based on query parameter, referer, or path
        let folder = 'jewelry-stock/items'; // Default to items

        // Check query parameter first (e.g., ?folder=containers)
        if (req.query.folder === 'containers') {
            folder = 'jewelry-stock/containers';
        }
        // Fallback: check referer header for 'container' keyword
        else if (req.headers.referer && req.headers.referer.includes('container')) {
            folder = 'jewelry-stock/containers';
        }
        // Fallback: check path
        else if (req.path.includes('container')) {
            folder = 'jewelry-stock/containers';
        }

        return {
            folder: folder,
            allowed_formats: ['jpg', 'jpeg', 'png', 'webp', 'heic'],
            transformation: [
                { width: 1200, height: 1200, crop: 'limit' }, // Max dimensions
                { quality: 'auto:good' }, // Auto quality optimization
                { fetch_format: 'auto' } // Auto format (WebP for supported browsers)
            ],
            public_id: `${Date.now()}-${file.originalname.split('.')[0]}` // Unique filename
        };
    }
});

// Create multer upload instance
const upload = multer({
    storage: storage,
    limits: {
        fileSize: 5 * 1024 * 1024 // 5MB limit
    },
    fileFilter: (req, file, cb) => {
        // Accept images only
        if (!file.mimetype.startsWith('image/')) {
            return cb(new Error('Only image files are allowed!'), false);
        }
        cb(null, true);
    }
});

module.exports = upload;
