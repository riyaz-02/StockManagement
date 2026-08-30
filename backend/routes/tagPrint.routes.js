const express = require('express');
const router = express.Router();
const { protect, requirePermission } = require('../middleware/auth');
const {
    getItemsForTagPrinting,
    recordTagPrint,
    getTagPrintHistory,
    generateTagsPDF,
    generateBlankTagsPDF
} = require('../controllers/tagPrintController');

// All routes require authentication
router.use(protect);

router.get('/items', requirePermission('tags.print'), getItemsForTagPrinting);
router.post('/record', requirePermission('tags.print'), recordTagPrint);
router.get('/history/:itemId', requirePermission('tags.print'), getTagPrintHistory);
router.post('/generate-pdf', requirePermission('tags.print'), generateTagsPDF);
router.post('/generate-blank-tags-pdf', requirePermission('tags.print'), generateBlankTagsPDF);

module.exports = router;
