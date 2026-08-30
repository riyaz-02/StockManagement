const express = require('express');
const router = express.Router();
const { sendNotification, getNotificationHistory } = require('../controllers/notificationController');
const { protect, authorize } = require('../middleware/auth');

// All routes require authentication + admin
router.use(protect);
router.use(authorize('admin'));

router.get('/', getNotificationHistory);
router.post('/send', sendNotification);

module.exports = router;
