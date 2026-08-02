'use strict';

const express = require('express');
const router  = express.Router();
const { protect } = require('../middleware/auth');
const ctrl = require('../controllers/invoiceController');

// All routes require authentication
router.use(protect);

router.get('/next-number', ctrl.getNextNumber);
router.get('/',            ctrl.getInvoices);
router.post('/',           ctrl.createInvoice);
router.get('/:id',         ctrl.getInvoice);
router.put('/:id',         ctrl.updateInvoice);
router.delete('/:id',      ctrl.deleteInvoice);

module.exports = router;
