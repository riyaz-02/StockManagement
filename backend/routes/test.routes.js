const express = require('express');
const router = express.Router();
const cloudinary = require('../config/cloudinary');
const { protect } = require('../middleware/auth');

// @route   GET /api/test/cloudinary
// @desc    Test Cloudinary connection
// @access  Private
router.get('/cloudinary', protect, async (req, res) => {
    try {
        // Test API connection
        const pingResult = await cloudinary.api.ping();

        // Get usage stats
        const usage = await cloudinary.api.usage();

        res.json({
            success: true,
            message: 'Cloudinary is connected and working!',
            connection: pingResult,
            usage: {
                storage: {
                    used: (usage.storage.usage / 1024 / 1024).toFixed(2) + ' MB',
                    limit: (usage.storage.limit / 1024 / 1024).toFixed(2) + ' MB',
                    percentage: ((usage.storage.usage / usage.storage.limit) * 100).toFixed(2) + '%'
                },
                bandwidth: {
                    used: (usage.bandwidth.usage / 1024 / 1024).toFixed(2) + ' MB',
                    limit: (usage.bandwidth.limit / 1024 / 1024).toFixed(2) + ' MB',
                    percentage: ((usage.bandwidth.usage / usage.bandwidth.limit) * 100).toFixed(2) + '%'
                }
            }
        });
    } catch (error) {
        res.status(500).json({
            success: false,
            message: 'Cloudinary connection failed',
            error: error.message
        });
    }
});

module.exports = router;
