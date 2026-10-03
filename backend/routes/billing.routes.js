/**
 * billing.routes.js — GST billing.
 * No delete anywhere. Creating and receiving payments are separate permissions.
 */
const express = require('express');
const router = express.Router();
const { protect, requirePermission } = require('../middleware/auth');
const ctrl = require('../controllers/billingController');

router.use(protect);

router.get('/meta', requirePermission('billing.view'), ctrl.meta);
router.get('/stats', requirePermission('billing.view'), ctrl.stats);
router.get('/cash-today', requirePermission('billing.view'), ctrl.cashToday);
router.get('/customer/:id', requirePermission('billing.view'), ctrl.customerSummary);

router.get('/invoices', requirePermission('billing.view'), ctrl.listInvoices);
router.get('/invoices/:id', requirePermission('billing.view'), ctrl.getInvoice);
router.get('/stock-line', requirePermission('billing.create'), ctrl.stockLine);
router.post('/calculate', requirePermission('billing.create'), ctrl.calculate);
router.post('/invoices', requirePermission('billing.create'), ctrl.createInvoice);
router.post('/invoices/:id/payments', requirePermission('billing.receivePayment'), ctrl.addPayment);
router.get('/dues', requirePermission('billing.view'), ctrl.dues);
router.get('/daybook', requirePermission('daybook.view'), ctrl.dayBook);
router.get('/last-making', requirePermission('billing.view'), ctrl.lastMaking);
router.post('/reconcile', requirePermission('billing.viewAllBranches'), ctrl.reconcile);
router.post('/invoices/:id/print', requirePermission('billing.view'), ctrl.markPrinted);

module.exports = router;
