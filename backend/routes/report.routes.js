const express = require('express');
const router = express.Router();
const {
    getDailySummary,
    generateTallyPDF,
    generateTallyExcel
} = require('../controllers/reportController');
const { protect } = require('../middleware/auth');

// All routes require authentication
router.use(protect);

router.get('/daily', getDailySummary);
router.get('/tally/:id/pdf', generateTallyPDF);
router.get('/tally/:id/excel', generateTallyExcel);

module.exports = router;
