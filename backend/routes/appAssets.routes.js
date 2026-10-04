const express = require('express');
const router = express.Router();
const c = require('../controllers/loginSlideController');
const { protect, requirePermission } = require('../middleware/auth');
const { mediaUpload, MB } = require('../middleware/mediaUpload');

const slideUpload = mediaUpload({ allow: ['image'], maxBytes: 12 * MB, folder: () => 'login', thumb: true });

// Public: the sign-in screen needs them before anyone is signed in
router.get('/login-slides', c.publicList);

router.get('/login-slides/admin', protect, requirePermission('appAssets.manage'), c.adminList);
router.post('/login-slides/reorder', protect, requirePermission('appAssets.manage'), c.reorder);
router.post('/login-slides', protect, requirePermission('appAssets.manage'), slideUpload.single('image'), c.create);
router.patch('/login-slides/:id', protect, requirePermission('appAssets.manage'), c.update);
router.delete('/login-slides/:id', protect, requirePermission('appAssets.manage'), c.remove);

module.exports = router;
