const express = require('express');
const router = express.Router();
const { sendNotification, getNotificationHistory } = require('../controllers/notificationController');
const { protect, requirePermission } = require('../middleware/auth');

router.use(protect);

router.get('/', requirePermission('notifications.viewHistory'), getNotificationHistory);
router.post('/send', requirePermission('notifications.send'), sendNotification);

module.exports = router;
