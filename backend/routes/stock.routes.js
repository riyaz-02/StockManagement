const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/auth');
const ctrl = require('../controllers/stockController');

router.use(protect);

// Dashboard — combined barcoded + bulk weight totals
router.get('/dashboard', ctrl.getDashboard);

// Daily movement summary
router.get('/daily-summary', ctrl.getDailySummary);

// Stock reconciliation report
router.get('/reconciliation', ctrl.getReconciliation);

// Bulk weight management
router.get('/bulk-weights', ctrl.getBulkWeights);
router.post('/bulk-weights', ctrl.addBulkWeight);
router.put('/bulk-weights/:id', ctrl.updateBulkWeight);
router.delete('/bulk-weights/:id', ctrl.deleteBulkWeight);

module.exports = router;
