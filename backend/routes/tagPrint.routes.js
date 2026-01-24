const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/auth');
const {
    getItemsForTagPrinting,
    recordTagPrint,
    getTagPrintHistory,
    generateTagsPDF
} = require('../controllers/tagPrintController');

// All routes require authentication
router.use(protect);

// Get all items for tag printing
router.get('/items', getItemsForTagPrinting);

// Record tag print event
router.post('/record', recordTagPrint);

// Get tag print history for an item
router.get('/history/:itemId', getTagPrintHistory);

// Generate PDF for selected items
router.post('/generate-pdf', generateTagsPDF);

module.exports = router;
