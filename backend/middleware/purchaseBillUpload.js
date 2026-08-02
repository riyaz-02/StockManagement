/**
 * purchaseBillUpload.js — Multer-Cloudinary middleware specifically for purchase bills.
 *
 * Unlike the general image uploader:
 *  - Accepts images AND PDFs (scanned bills)
 *  - Stores into jewelry-stock/purchase-bills/ folder
 *  - No image transformation (PDFs must be uploaded raw)
 *  - 10 MB limit (bills can be larger than item photos)
 */

const multer = require('multer');
const { CloudinaryStorage } = require('multer-storage-cloudinary');
const cloudinary = require('../config/cloudinary');

const storage = new CloudinaryStorage({
    cloudinary,
    params: async (req, file) => {
        const isPdf = file.mimetype === 'application/pdf';
        return {
            folder: 'jewelry-stock/purchase-bills',
            resource_type: isPdf ? 'raw' : 'image',
            allowed_formats: ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf'],
            // Only apply transformations for images (not PDFs)
            ...(isPdf ? {} : {
                transformation: [
                    { width: 2000, height: 2000, crop: 'limit' },
                    { quality: 'auto:good' },
                    { fetch_format: 'auto' },
                ],
            }),
            public_id: `bill-${Date.now()}-${file.originalname.replace(/\.[^/.]+$/, '').replace(/\s+/g, '_')}`,
        };
    },
});

const purchaseBillUpload = multer({
    storage,
    limits: { fileSize: 10 * 1024 * 1024 }, // 10 MB
    fileFilter: (req, file, cb) => {
        const allowed = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'image/heic', 'application/pdf'];
        if (allowed.includes(file.mimetype)) {
            cb(null, true);
        } else {
            cb(new Error('Only images (JPG, PNG, WEBP, HEIC) and PDFs are allowed for purchase bills'), false);
        }
    },
});

module.exports = purchaseBillUpload;
