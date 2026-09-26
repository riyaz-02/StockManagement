/**
 * gstReports.routes.js — GST Summary page. Reading the reports, recording filed returns and changing the
 * settings are three separate permissions.
 */
const express = require('express');
const router = express.Router();
const { protect, requirePermission } = require('../middleware/auth');
const ctrl = require('../controllers/gstReportsController');

router.use(protect);

router.get('/settings', requirePermission('gst.viewReports'), ctrl.getSettings);
router.put('/settings', requirePermission('gst.editSettings'), ctrl.updateSettings);

router.get('/summary', requirePermission('gst.viewReports'), ctrl.summary);
router.get('/register', requirePermission('gst.viewReports'), ctrl.register);
router.get('/returns', requirePermission('gst.viewReports'), ctrl.returns);
router.get('/itc', requirePermission('gst.viewReports'), ctrl.itc);
router.get('/calendar', requirePermission('gst.viewReports'), ctrl.calendar);
router.get('/export', requirePermission('gst.viewReports'), ctrl.exportCsv);
router.get('/monthly-record', requirePermission('gst.viewReports'), ctrl.monthlyRecord);

router.get('/filings', requirePermission('gst.viewReports'), ctrl.listFilings);
router.post('/filings', requirePermission('gst.manageFilings'), ctrl.createFiling);
router.put('/filings/:id', requirePermission('gst.manageFilings'), ctrl.updateFiling);

module.exports = router;
