const express = require('express');
const router = express.Router();
const { protect, requirePermission } = require('../middleware/auth');
const ctrl = require('../controllers/stockController');

router.use(protect);

// Dashboard — combined barcoded + bulk weight totals
router.get('/dashboard', requirePermission('stock.view'), ctrl.getDashboard);

// Daily movement summary
router.get('/daily-summary', requirePermission('stock.view'), ctrl.getDailySummary);

// Stock reconciliation report
router.get('/reconciliation', requirePermission('stock.view'), ctrl.getReconciliation);

// Bulk weight management
router.get('/bulk-weights', requirePermission('stock.view'), ctrl.getBulkWeights);
router.post('/bulk-weights', requirePermission('stock.manageBulkWeights'), ctrl.addBulkWeight);
router.put('/bulk-weights/:id', requirePermission('stock.manageBulkWeights'), ctrl.updateBulkWeight);
router.delete('/bulk-weights/:id', requirePermission('stock.manageBulkWeights'), ctrl.deleteBulkWeight);

module.exports = router;
