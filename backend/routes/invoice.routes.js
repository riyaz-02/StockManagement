'use strict';

const express = require('express');
const router  = express.Router();
const { protect, requirePermission } = require('../middleware/auth');
const ctrl = require('../controllers/invoiceController');

// All routes require authentication
router.use(protect);

router.get('/next-number', requirePermission('invoices.view'), ctrl.getNextNumber);
router.get('/',            requirePermission('invoices.view'), ctrl.getInvoices);
router.post('/',           requirePermission('invoices.create'), ctrl.createInvoice);
router.get('/:id',         requirePermission('invoices.view'), ctrl.getInvoice);
router.put('/:id',         requirePermission('invoices.edit'), ctrl.updateInvoice);
router.delete('/:id',      requirePermission('invoices.delete'), ctrl.deleteInvoice);

module.exports = router;
