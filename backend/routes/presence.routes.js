const express = require('express');
const router = express.Router();
const c = require('../controllers/presenceController');
const { protect, requirePermission } = require('../middleware/auth');

// Reporting your own presence needs no special permission, same as /live/ticket — every signed-in person may.
router.post('/ping', protect, c.ping);
router.get('/', protect, requirePermission('users.manage'), c.list);

module.exports = router;
