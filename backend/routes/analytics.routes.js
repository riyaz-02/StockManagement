const express = require('express');
const router = express.Router();
const { protect, authorize } = require('../middleware/auth');
const { getDashboardStats } = require('../controllers/analyticsController');

// Get dashboard statistics
router.get('/dashboard', protect, authorize('admin', 'user'), getDashboardStats);

module.exports = router;
