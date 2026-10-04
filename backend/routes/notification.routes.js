const express = require('express');
const router = express.Router();
const { sendNotification, getNotificationHistory, getFeed, markFeedSeen } = require('../controllers/notificationController');
const { protect, requirePermission } = require('../middleware/auth');

router.use(protect);

// the bell: any signed-in person (what they see is filtered by who they are)
router.get('/feed', getFeed);
router.post('/feed/seen', markFeedSeen);

router.get('/', requirePermission('notifications.viewHistory'), getNotificationHistory);
router.post('/send', requirePermission('notifications.send'), sendNotification);

module.exports = router;
