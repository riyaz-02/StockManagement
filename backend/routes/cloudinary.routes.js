const express = require('express');
const router = express.Router();
const upload = require('../middleware/cloudinaryUpload');
const cloudinary = require('../config/cloudinary');
const { protect, requirePermission } = require('../middleware/auth');

// @route   POST /api/upload/single
// @desc    Upload single image to Cloudinary
// @access  Private
router.post('/single', protect, requirePermission('media.upload'), upload.single('image'), async (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).json({
                success: false,
                message: 'No file uploaded'
            });
        }

        res.json({
            success: true,
            data: {
                url: req.file.path, // Cloudinary URL
                publicId: req.file.filename,
                format: req.file.format,
                width: req.file.width,
                height: req.file.height
            }
        });
    } catch (error) {
        console.error('Upload error:', error);
        res.status(500).json({
            success: false,
            message: 'Error uploading image',
            error: error.message
        });
    }
});

// @route   POST /api/upload/multiple
// @desc    Upload multiple images to Cloudinary
// @access  Private
router.post('/multiple', protect, requirePermission('media.upload'), upload.array('images', 5), async (req, res) => {
    try {
        if (!req.files || req.files.length === 0) {
            return res.status(400).json({
                success: false,
                message: 'No files uploaded'
            });
        }

        const images = req.files.map(file => ({
            url: file.path,
            publicId: file.filename,
            format: file.format,
            width: file.width,
            height: file.height
        }));

        res.json({
            success: true,
            data: { images }
        });
    } catch (error) {
        console.error('Upload error:', error);
        res.status(500).json({
            success: false,
            message: 'Error uploading images',
            error: error.message
        });
    }
});

// @route   DELETE /api/upload/:publicId
// @desc    Delete image from Cloudinary
// @access  Private
router.delete('/:publicId', protect, requirePermission('media.upload'), async (req, res) => {
    try {
        const publicId = req.params.publicId.replace(/--/g, '/'); // Convert -- back to /

        const result = await cloudinary.uploader.destroy(publicId);

        if (result.result === 'ok') {
            res.json({
                success: true,
                message: 'Image deleted successfully'
            });
        } else {
            res.status(404).json({
                success: false,
                message: 'Image not found'
            });
        }
    } catch (error) {
        console.error('Delete error:', error);
        res.status(500).json({
            success: false,
            message: 'Error deleting image',
            error: error.message
        });
    }
});

// @route   GET /api/upload/stats
// @desc    Get Cloudinary usage stats
// @access  Private
router.get('/stats', protect, async (req, res) => {
    try {
        const usage = await cloudinary.api.usage();

        res.json({
            success: true,
            data: {
                storage: {
                    used: (usage.storage.usage / 1024 / 1024).toFixed(2) + ' MB',
                    limit: (usage.storage.limit / 1024 / 1024).toFixed(2) + ' MB',
                    percentage: ((usage.storage.usage / usage.storage.limit) * 100).toFixed(2) + '%'
                },
                bandwidth: {
                    used: (usage.bandwidth.usage / 1024 / 1024).toFixed(2) + ' MB',
                    limit: (usage.bandwidth.limit / 1024 / 1024).toFixed(2) + ' MB',
                    percentage: ((usage.bandwidth.usage / usage.bandwidth.limit) * 100).toFixed(2) + '%'
                },
                transformations: {
                    used: usage.transformations.usage,
                    limit: usage.transformations.limit,
                    percentage: ((usage.transformations.usage / usage.transformations.limit) * 100).toFixed(2) + '%'
                }
            }
        });
    } catch (error) {
        console.error('Stats error:', error);
        res.status(500).json({
            success: false,
            message: 'Error fetching stats',
            error: error.message
        });
    }
});

module.exports = router;
