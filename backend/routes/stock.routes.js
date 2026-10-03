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

// The Summary (metal balance and difference), its history, and the daily snapshot
router.get('/summary', requirePermission('stock.view'), ctrl.getSummary);
router.get('/summary/movements', requirePermission('stock.view'), ctrl.getSummaryMovements);
router.get('/summary/history', requirePermission('stock.view'), ctrl.getSummaryHistory);
router.post('/summary/snapshot', requirePermission('stock.snapshot'), ctrl.saveSummarySnapshot);

// Wastage reports (the website's wastage_reports): report, approve, reject
const wastage = require('../controllers/wastageController');
router.get('/wastage', requirePermission('wastage.view'), wastage.list);
router.get('/wastage/:id', requirePermission('wastage.view'), wastage.get);
router.post('/wastage', requirePermission('wastage.report'), wastage.create);
router.put('/wastage/:id', requirePermission('wastage.report'), wastage.update);
router.post('/wastage/:id/approve', requirePermission('wastage.approve'), wastage.approve);
router.post('/wastage/:id/reject', requirePermission('wastage.approve'), wastage.reject);

// Bulk weight management
router.get('/bulk-weights', requirePermission('stock.view'), ctrl.getBulkWeights);
router.post('/bulk-weights', requirePermission('stock.manageBulkWeights'), ctrl.addBulkWeight);
router.put('/bulk-weights/:id', requirePermission('stock.manageBulkWeights'), ctrl.updateBulkWeight);
router.delete('/bulk-weights/:id', requirePermission('stock.manageBulkWeights'), ctrl.deleteBulkWeight);

module.exports = router;
