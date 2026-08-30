const express = require('express');
const router = express.Router();
const { protect, requirePermission } = require('../middleware/auth');
const { getDashboardStats } = require('../controllers/analyticsController');

// Get dashboard statistics
router.get('/dashboard', protect, requirePermission('reports.view'), getDashboardStats);

module.exports = router;
