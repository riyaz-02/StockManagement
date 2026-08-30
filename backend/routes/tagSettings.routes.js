const express = require('express');
const router = express.Router();
const tagSettingsController = require('../controllers/tagSettingsController');
const { protect, requirePermission } = require('../middleware/auth');

// All routes require authentication
router.use(protect);

// GET /api/tag-settings - Get tag printing settings
router.get('/', requirePermission('tags.print'), tagSettingsController.getTagSettings);

// PUT /api/tag-settings - Update tag printing settings
router.put('/', requirePermission('tags.manageSettings'), tagSettingsController.updateTagSettings);

module.exports = router;
